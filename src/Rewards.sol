// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// @author 0xleadWizard
// @title Staking Rewards
// @notice TimeLocked Staking contract, where users can stake STAKE_TOKEN and earn REWARD_TOKEN with a lock period
contract Rewards {
    using SafeERC20 for IERC20;
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Staked(bytes32 indexed id, address staker, uint256 amount);
    event Unstaked(address staker, uint256 amount);
    event Claim(address staker, uint256 claimAmount);

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    struct Stake {
        uint256 amount;
        uint256 unlockTime;
        bytes32 next;
    }

    bool stakeActive;
    uint256 public nonce;
    uint256 public totalStaked;
    uint256 tokenPerSec;
    uint256 rewardPerTokenStored;
    uint256 lastUpdateTime;
    uint256 periodFinish;

    address public OWNER;
    address public immutable STAKE_TOKEN;
    address public immutable REWARD_TOKEN;
    uint256 public immutable WITHDRAW_PERIOD;

    mapping(bytes32 => Stake) public stakes;
    mapping(address => bytes32) public userStakeHead;
    mapping(address => uint256) public userStaked;
    mapping(address => uint256) userRewardPerTokenPaid;
    mapping(address => uint256) rewards;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error ZeroAmount();
    error StakingInActive();
    error NotOwner();

    /*//////////////////////////////////////////////////////////////
                                 LOGIC
    //////////////////////////////////////////////////////////////*/

    constructor(
        address stakeToken,
        address rewardToken,
        uint256 withdrawPeriod,
        uint256 rewards,
        address owner
    ) {
        STAKE_TOKEN = stakeToken;
        REWARD_TOKEN = rewardToken;
        WITHDRAW_PERIOD = withdrawPeriod;
        tokenPerSec = rewards / 365 days;
        OWNER = owner;
    }

    function initialize() external {
        if (msg.sender != OWNER) revert NotOwner();
        stakeActive = true;
        periodFinish = block.timestamp + 365 days;
        uint256 amount = IERC20(REWARD_TOKEN).allowance(msg.sender, address(this));
        IERC20(REWARD_TOKEN).transferFrom(msg.sender, address(this), amount);
    }

    // @notice Set staking status
    // @param flag True for staking Active, false for inactive
    // @dev Can only be called by owner
    function setStakingStatus(bool flag) external {
        if (msg.sender != OWNER) revert NotOwner();
        stakeActive = flag;
    }

    // @notice Stake
    // @param amount The amount of STAKE_TOKEN, user wants to stake
    // @dev Should revert if the Staking Has not started yet
    // @dev LinkedList is utlized to store staking info, allowing multiple stakes from same user
    function stake(uint256 amount) external {
        if (!stakeActive) revert StakingInActive();
        if (amount == 0) revert ZeroAmount();

        _updateReward(msg.sender);

        IERC20(STAKE_TOKEN).safeTransferFrom(msg.sender, address(this), amount);

        bytes32 key = keccak256(abi.encode(msg.sender, ++nonce));
        stakes[key] = Stake(amount, block.timestamp + WITHDRAW_PERIOD, userStakeHead[msg.sender]);
        userStakeHead[msg.sender] = key;

        userStaked[msg.sender] += amount;
        totalStaked += amount;

        emit Staked(key, msg.sender, amount);
    }

    // @notice Unstake
    // @dev Calls claim function internally, to claim any unclaimed reward and then starts unstaking
    function unstake() external {
        // Call claim to be safe
        _claim(msg.sender);
        _updateReward(msg.sender);

        bytes32 head = userStakeHead[msg.sender];
        bytes32 previousHead;
        uint256 unstakedAmount;
        bytes32 NULL;

        while (head != NULL) {
            Stake memory _stake = stakes[head];

            if (_stake.unlockTime <= block.timestamp || block.timestamp > periodFinish) {
                delete stakes[head];
                unstakedAmount += _stake.amount;
            } else {
                previousHead = head;
            }

            if (previousHead == NULL) {
                userStakeHead[msg.sender] = NULL;
            } else if (previousHead != bytes32(~uint256(0))) {
                stakes[previousHead].next = NULL;
                previousHead = bytes32(~uint256(0));
            }

            head = _stake.next;
        }

        totalStaked -= unstakedAmount;
        userStaked[msg.sender] -= unstakedAmount;
        IERC20(STAKE_TOKEN).transfer(msg.sender, unstakedAmount);

        emit Unstaked(msg.sender, unstakedAmount);
    }

    // @notice Directly called by user to claim their rewards
    function claim() external {
        _claim(msg.sender);
    }

    // @notice calculates claim amount for the user.
    // @param user The address to calculate the reward for
    function getClaimAmount(address user) public view returns (uint256) {
        return userStaked[user] * (rewardPerToken() - userRewardPerTokenPaid[user]) / 1e18 + rewards[user];
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }

        return
            rewardPerTokenStored + (((lastTimeRewardApplicable() - lastUpdateTime) * tokenPerSec * 1e18) / totalStaked);
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    // @notice Update reward variables for the user
    // @param user The address to update the reward for
    function _updateReward(address user) internal {
        rewardPerTokenStored = rewardPerToken();
        userRewardPerTokenPaid[user] = rewardPerTokenStored;
        lastUpdateTime = lastTimeRewardApplicable();
        rewards[user] = getClaimAmount(user);
    }

    function _claim(address user) internal {
        uint256 claimAmount = getClaimAmount(user);
        IERC20(REWARD_TOKEN).transfer(user, claimAmount);
        emit Claim(user, claimAmount);
    }

    function getStakeInfo(bytes32 id) public view returns (Stake memory) {
        return stakes[id];
    }
}
