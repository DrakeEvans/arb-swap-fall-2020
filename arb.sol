contract Arb is IUniswapV2Callee {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  address payable immutable owner;

  mapping(address => bool) private approved_already;

  constructor(address payable _owner) public {
    owner = _owner;
  }

  receive() external payable {}

  struct Swap {
    address pair;
    address from;
    address to;
  }

  struct Repay {
    address pair;
    address borrow_token;
    address payment_token;
    uint256 initial_borrow;
    uint256 payment_amount;
    uint256 min_profit_margin;
  }

  struct RepayCompute {
    address pair;
    address borrow_token;
    address payment_token;
    uint256 initial_borrow;
  }

  function _cashout(address[] memory _addrs) private {
    for (uint8 i = 0; i < _addrs.length; i++) {
      if (approved_already[_addrs[i]] == true) {
        IERC20(_addrs[i]).safeTransfer(
          owner,
          IERC20(_addrs[i]).balanceOf(address(this))
        );
      }
    }
  }

  function payout(bytes calldata payouts) external {
    require(msg.sender == owner, "only e can call");
    _cashout(abi.decode(payouts, (address[])));
    owner.transfer(address(this).balance);
  }

  function payout_and_selfdestruct(bytes calldata payouts) external {
    require(msg.sender == owner, "only e can call");
    _cashout(abi.decode(payouts, (address[])));
    selfdestruct(owner);
  }

  function uniswapV2Call(
    address _sender,
    uint256 _amount0,
    uint256 _amount1,
    bytes calldata _data
  ) external override {
    require(_sender == address(this), "only this contract may initiate");

    if (true) {
      _amount0;
      _amount1;
      _sender;
    }

    (Repay memory debt, bytes memory swaps_data) =
      abi.decode(_data, (Repay, bytes));

    Swap[] memory swaps = abi.decode(swaps_data, (Swap[]));

    address token0;
    address token1;
    uint256 _their_compute;

    for (uint8 i = 0; i < swaps.length; i++) {
      _their_compute = _amountOut(
        IERC20(swaps[i].from).balanceOf(address(this)),
        IERC20(swaps[i].from).balanceOf(swaps[i].pair),
        IERC20(swaps[i].to).balanceOf(swaps[i].pair)
      );

      IERC20(swaps[i].from).safeTransfer(
        swaps[i].pair,
        IERC20(swaps[i].from).balanceOf(address(this))
      );

      (token0, token1) = swaps[i].from < swaps[i].to
        ? (swaps[i].from, swaps[i].to)
        : (swaps[i].to, swaps[i].from);

      IUniswapV2Pair(swaps[i].pair).swap(
        swaps[i].from == token0 ? 0 : _their_compute,
        swaps[i].to == token1 ? _their_compute : 0,
        address(this),
        bytes("")
      );
    }

    require(
      IERC20(debt.payment_token).balanceOf(address(this)) >
        (debt.payment_amount + debt.min_profit_margin),
      "not a profitable trade"
    );

    // failing because i don't have the required amount even in balance -
    IERC20(debt.payment_token).safeTransfer(debt.pair, debt.payment_amount);
  }

  function _amountOut(
    uint256 _amount,
    uint256 reserveIn,
    uint256 reserveOut
  ) private pure returns (uint256) {
    uint256 amountInWithFee = _amount.mul(997);
    uint256 numerator = amountInWithFee.mul(reserveOut);
    uint256 denominator = reserveIn.mul(1000).add(amountInWithFee);
    return numerator / denominator;
  }

  function how_much_return(bytes calldata _scenario)
    external
    view
    returns (uint256, RepayCompute memory)
  {
    RepayCompute memory _repay = abi.decode(_scenario, (RepayCompute));
    if (_repay.borrow_token == _repay.payment_token) {
      return (
        _repay.initial_borrow + (((_repay.initial_borrow * 3) / 997) + 1),
        _repay
      );
    } else {
      uint256 _borrow_bal = IERC20(_repay.borrow_token).balanceOf(_repay.pair);
      uint256 _pay_bal = IERC20(_repay.payment_token).balanceOf(_repay.pair);
      return (
        ((1000 * _pay_bal * _repay.initial_borrow) /
          (997 * (_borrow_bal - _repay.initial_borrow))) + 1,
        _repay
      );
    }
  }

  function dry_run(bytes calldata _swaps, bytes calldata borrow_and_repay)
    external
    view
    returns (
      uint256 final_amount,
      uint256 payment_amount,
      bool is_profitable
    )
  {
    require(msg.sender == owner, "only e can call");

    (uint256 _payment_amount, RepayCompute memory _repayment) =
      this.how_much_return(borrow_and_repay);

    Swap[] memory swaps = abi.decode(_swaps, (Swap[]));

    uint256 stub_out_balance = _repayment.initial_borrow;

    for (uint256 i = 0; i < swaps.length; i++) {
      stub_out_balance = _amountOut(
        stub_out_balance,
        IERC20(swaps[i].from).balanceOf(swaps[i].pair),
        IERC20(swaps[i].to).balanceOf(swaps[i].pair)
      );
    }

    return (
      stub_out_balance,
      _payment_amount,
      stub_out_balance > _payment_amount
    );
  }

  function start_arb(
    bytes calldata swaps,
    bytes calldata repay_compute,
    bytes calldata allowance,
    uint256 min_profit_amount
  ) external {
    require(msg.sender == owner, "only e can call");
    address[] memory _allowance_addrs = abi.decode(allowance, (address[]));
    (uint256 repayment, RepayCompute memory _repay) =
      this.how_much_return(repay_compute);

    for (uint8 i = 0; i < _allowance_addrs.length; i++) {
      if (approved_already[_allowance_addrs[i]] == false) {
        IERC20(_allowance_addrs[i]).safeIncreaseAllowance(
          address(this),
          uint256(-1)
        );
        approved_already[_allowance_addrs[i]] = true;
      }
    }

    bytes memory callback_d =
      abi.encode(
        Repay({
          pair: _repay.pair,
          borrow_token: _repay.borrow_token,
          payment_token: _repay.payment_token,
          initial_borrow: _repay.initial_borrow,
          payment_amount: repayment,
          min_profit_margin: min_profit_amount
        }),
        swaps
      );

    uint256 amount0_out;
    uint256 amount1_out;

    if (_repay.borrow_token != _repay.payment_token) {
      (amount0_out, amount1_out) = _repay.borrow_token < _repay.payment_token
        ? (_repay.initial_borrow, uint256(0))
        : (uint256(0), _repay.initial_borrow);
    } else {
      address token0 = IUniswapV2Pair(_repay.pair).token0();
      amount0_out = _repay.borrow_token == token0 ? _repay.initial_borrow : 0;
      amount1_out = _repay.borrow_token == token0 ? _repay.initial_borrow : 0;
    }

    IUniswapV2Pair(_repay.pair).swap(
      amount0_out,
      amount1_out,
      address(this),
      callback_d
    );
  }
}
