// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "ds-test/test.sol";
import "./FaucetV1.sol";

interface Hevm {
    function warp(uint256) external;
}

contract User {
    Token token;
    FaucetV1 faucet;

    function deployContracts(uint256 _balance) public returns(Token, FaucetV1) {
        token = new Token("RAD", _balance);
        faucet = new FaucetV1(50);
        return (token, faucet);
    }

    function setContracts(FaucetV1 _faucet, Token _token) public {
      faucet = _faucet;
      token = _token;
    }

    function transferFrom(address _from, address _to, uint256 _amount) public {
      token.transferFrom(_from, _to, _amount);
    }

    function setMaxAmount(uint256 _amount) public {
      faucet.setMaxAmount(_amount);
    }

    function setOwner(address _newOwner) public {
      faucet.setOwner(_newOwner);
    }

    function withdraw(uint256 _amount) public {
      faucet.withdraw(token, _amount);
    }
}

contract FaucetV1Test is DSTest {
    FaucetV1 faucet;
    Token token;
    User faucet_owner;
    User requester;
    Hevm hevm = Hevm(HEVM_ADDRESS);

    function setUp() public {
        faucet_owner    = new User();
        requester       = new User();
        (token, faucet) = faucet_owner.deployContracts(100);

        assertEq(token.balanceOf(address(faucet_owner)), 100);
        assertEq(address(faucet_owner), faucet.owner());

        faucet_owner.transferFrom(address(faucet_owner), address(faucet), 100);
        requester.setContracts(faucet, token);

        // Warps to a first timestamp since initial value is zero.
        hevm.warp(1635321120);
    }

    function test_sanity() public {
        // Check that the calculateTimeLock works
        assertEq(faucet.calculateTimeLock(10 ether), 10 hours);
        assertEq(faucet.calculateTimeLock(20 ether), 40 hours);
        assertEq(faucet.calculateTimeLock(100 ether), 1000 hours);

        // The first request by a new user will return a timestamp of 0
        // which will be always be lower than the current timestamp, checking for sanity solely.
        // To obtain a timestamp bigger than 0 we use the hevm.warp function.
        uint256 timestamp = faucet.lastWithdrawalByUser(
           address(requester) 
        );
        assertTrue(timestamp + faucet.calculateTimeLock(10 ether) < block.timestamp);
    }

    function test_set_max_amount() public {
      faucet_owner.setMaxAmount(100);
      assertEq(faucet.maxWithdrawAmount(), 100);
    }

    function test_withdrawal() public {
        assertEq(token.balanceOf(address(requester)), 0);
        requester.withdraw(10);
        assertEq(token.balanceOf(address(requester)), 10);
    }

    // The withdrawal fails since no time has passed in between withdrawals
    function testFail_repeat_withdraw() public {
        requester.withdraw(10);
        requester.withdraw(10);
    }

    function test_repeat_withdraw() public {
        for (uint256 i = 0; i < 3; i++) {
            requester.withdraw(10);
            hevm.warp(block.timestamp + 129660 * (i + 1));
        }
        assertEq(token.balanceOf(address(requester)), 30);
    }

    function test_set_new_owner() public {
        User new_faucet_owner = new User();
        faucet_owner.setOwner(address(new_faucet_owner));
        assertEq(
            faucet.owner(),
            address(new_faucet_owner)
        );
    }
}

contract Token is IERC20 {
    string public symbol;
    mapping(address => uint256) public override balanceOf;

    constructor(string memory _symbol, uint256 supply) {
        symbol = _symbol;
        balanceOf[msg.sender] = supply;
    }

    function transferFrom(address spender, address addr, uint256 amount) public override returns (bool) {
        require(balanceOf[spender] >= amount);

        balanceOf[spender] -= amount;
        balanceOf[addr] += amount;

        return true;
    }
}
