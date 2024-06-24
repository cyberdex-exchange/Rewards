// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Rewards} from "../src/Rewards.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CYDX_TOKEN is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1_000_000e18);
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract RewardsTest is Test {
    Rewards public rewards;
    CYDX_TOKEN public CYDX;
    uint256 public WITHDRAW_PERIOD;
    uint256 public TOTAL_REWARDS;
    uint256 public VAULT_LIFE_TIME;

    struct Stake {
        uint256 amount;
        uint256 unlockTime;
        bytes32 next;
    }

    function setUp() public {
        CYDX = new CYDX_TOKEN("CYDX", "CYDX");
        WITHDRAW_PERIOD = 180 days;
        TOTAL_REWARDS = 1_000_000e18;
        VAULT_LIFE_TIME = 365 days;

        rewards = new Rewards(address(CYDX), address(CYDX), WITHDRAW_PERIOD, TOTAL_REWARDS, address(this), VAULT_LIFE_TIME);

        CYDX.approve(address(rewards), TOTAL_REWARDS);
        rewards.initialize();
    }

    function test_setup() public {
        assertEq(rewards.STAKE_TOKEN(), address(CYDX));
        assertEq(rewards.REWARD_TOKEN(), address(CYDX));
        assertEq(rewards.WITHDRAW_PERIOD(), WITHDRAW_PERIOD);
    }

    function test_stake() public {
        uint256 amount = 1000e18;
        CYDX.mint(address(this), amount);
        CYDX.approve(address(rewards), amount);
        rewards.stake(amount);

        uint256 nonce = rewards.nonce();
        bytes32 stakeId = keccak256(abi.encode(address(this), nonce));
        Rewards.Stake memory stake = rewards.getStakeInfo(stakeId);

        assertEq(stake.amount, amount);
        assertEq(stake.unlockTime, block.timestamp + WITHDRAW_PERIOD);
        assertEq(rewards.userStaked(address(this)), amount);
        assertEq(rewards.totalStaked(), amount);
    }

    function test_stake_and_unstake() public {
        uint256 amount = 1000e18;
        CYDX.mint(address(this), amount);
        CYDX.approve(address(rewards), amount);
        rewards.stake(amount);

        uint256 nonce = rewards.nonce();
        bytes32 stakeId = keccak256(abi.encode(address(this), nonce));
        Rewards.Stake memory stake = rewards.getStakeInfo(stakeId);

        assertEq(stake.amount, amount);
        assertEq(stake.unlockTime, block.timestamp + WITHDRAW_PERIOD);
        assertEq(rewards.userStaked(address(this)), amount);
        assertEq(rewards.totalStaked(), amount);

        vm.warp(block.timestamp + WITHDRAW_PERIOD + 1);
        uint256 reward = rewards.getClaimAmount(address(this));
        rewards.unstake();

        assertEq(rewards.userStaked(address(this)), 0);
        assertEq(rewards.totalStaked(), 0);
        assertEq(CYDX.balanceOf(address(this)), amount + reward);
    }

    function test_FUZZ_Multiple_Stake(uint8 n) public {
        vm.assume(n > 0 && n < 10);
        for (uint8 i = 0; i < n; i++) {
            uint256 amount = 1000e18;
            CYDX.mint(address(this), amount);
            CYDX.approve(address(rewards), amount);
            rewards.stake(amount);

            uint256 nonce = rewards.nonce();
            bytes32 stakeId = keccak256(abi.encode(address(this), nonce));
            Rewards.Stake memory stake = rewards.getStakeInfo(stakeId);

            assertEq(stake.amount, amount);
            assertEq(stake.unlockTime, block.timestamp + WITHDRAW_PERIOD);
            assertEq(rewards.userStaked(address(this)), amount * (i + 1));
            assertEq(rewards.totalStaked(), amount * (i + 1));
        }
    }

    function test_FUZZ_Multiple_Unstake(uint8 n, uint8 offset) public {
        uint256 amount = 1000e18;
        // Stake
        vm.assume(n > 1 && n < 10);
        vm.assume(offset > 0 && offset < n - 1);

        uint256 timeGapBetweenStakes = n * 1 days;
        for (uint8 i = 0; i < n; i++) {
            vm.warp(block.timestamp + timeGapBetweenStakes);
            CYDX.mint(address(this), amount);
            CYDX.approve(address(rewards), amount);
            rewards.stake(amount);

            uint256 nonce = rewards.nonce();
            bytes32 stakeId = keccak256(abi.encode(address(this), nonce));
            Rewards.Stake memory stake = rewards.getStakeInfo(stakeId);

            assertEq(stake.amount, amount);
            assertEq(stake.unlockTime, block.timestamp + WITHDRAW_PERIOD);
            assertEq(rewards.userStaked(address(this)), amount * (i + 1));
            assertEq(rewards.totalStaked(), amount * (i + 1));
        }

        // Unstake
        vm.warp(block.timestamp + WITHDRAW_PERIOD  - (offset * timeGapBetweenStakes));
        uint256 reward = rewards.getClaimAmount(address(this));
        rewards.unstake();
        assertEq(rewards.userStaked(address(this)), offset * amount);
        assertEq(rewards.totalStaked(), offset * amount);
        assertEq(CYDX.balanceOf(address(this)), (n - offset) * amount + reward);
    }
}
