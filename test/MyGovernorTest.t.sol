// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {MyGovernor} from "../src/MyGovernor.sol";
import {Box} from "../src/Box.sol";
import {GovToken} from "../src/GovToken.sol";
import {TimeLock} from "../src/TimeLock.sol";

contract MyGovernorTest is Test {
    MyGovernor public governor;
    Box public box;
    GovToken public govToken;
    TimeLock public timeLock;

    address public USER = makeAddr("user");
    uint256 public constant INITIAL_SUPPLY = 100 ether;

    uint256 public constant MIN_DELAY = 3600;
    uint256 public constant VOTING_DELAY = 1;
    uint256 public constant VOTING_PERIOD = 50400;

    uint256[] public values;
    bytes[] callDatas;
    address[] targets;

    address[] proposers;
    address[] executors;

    function setUp() public {
        // Set up the governor contract
        govToken = new GovToken();
        govToken.mint(USER, INITIAL_SUPPLY);

        vm.startPrank(USER);
        govToken.delegate(USER);
        timeLock = new TimeLock(MIN_DELAY, proposers, executors);
        governor = new MyGovernor(govToken, timeLock);

        bytes32 proposerRole = timeLock.PROPOSER_ROLE();
        bytes32 executorRole = timeLock.EXECUTOR_ROLE();
        bytes32 adminRole = timeLock.TIMELOCK_ADMIN_ROLE();

        timeLock.grantRole(proposerRole, address(governor));
        timeLock.grantRole(executorRole, address(0));
        timeLock.revokeRole(adminRole, USER);
        vm.stopPrank();

        box = new Box();
        box.transferOwnership(address(timeLock));
    }

    function testCantUpdateBoxWithoutGovernance() public {
        vm.expectRevert();
        box.store(1);
    }

    function testGovernanceUpdatesBox() public {
        //one big test to check how governance updates box
        uint256 newNumberToStore = 777;
        string memory description = "store 1 to Box";
        bytes memory encodedFunctionCall = abi.encodeWithSignature("store(uint256)", newNumberToStore);
        values.push(0);
        callDatas.push(encodedFunctionCall);
        targets.push(address(box));
        //(targets, values, calldatas, description)

        //1. Propose to DAO
        uint256 proposalId = governor.propose(targets, values, callDatas, description);
        //view state of proposal
        console.log("Proposal state:", uint256(governor.state(proposalId))); //will be pending
        //move the block time and number forwards so the proposal state can change
        //the governor contract has a preset voting delay of 1 block
        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.roll(block.number + VOTING_DELAY + 1);

        console.log("Proposal state:", uint256(governor.state(proposalId))); //active

        //2. vote
        string memory reason = "What a pawtato";

        uint8 voteWay = 1; //voting yes
        vm.prank(USER);
        governor.castVoteWithReason(proposalId, voteWay, reason);

        //emulate voting period
        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        //3. Queue the tx
        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        governor.queue(targets, values, callDatas, descriptionHash);

        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.roll(block.number + MIN_DELAY + 1);

        //4. Execute tx
    }
}
