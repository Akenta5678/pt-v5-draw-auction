// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { DrawAuctionHarness } from "test/harness/DrawAuctionHarness.sol";
import { Helpers, RNGInterface, UD2x18, AuctionResults } from "test/helpers/Helpers.t.sol";

import { RngAuction } from "local-draw-auction/RngAuction.sol";

contract DrawAuctionTest is Helpers {
  /* ============ Errors ============ */

  /// @notice Thrown if the auction period is zero.
  error AuctionDurationZero();

  /// @notice Thrown if the RngAuction address is the zero address.
  error RngAuctionZeroAddress();

  /// @notice Thrown if the current draw auction has already been completed.
  error DrawAlreadyCompleted();

  /// @notice Thrown if the current draw auction has expired.
  error DrawAuctionExpired();

  /// @notice Thrown if the RNG request is not complete for the current sequence.
  error RngNotCompleted();

  /* ============ Events ============ */

  event AuctionCompleted(
    address indexed recipient,
    uint32 indexed sequenceId,
    uint64 elapsedTime,
    UD2x18 rewardPortion
  );

  /* ============ Variables ============ */

  DrawAuctionHarness public drawAuction;
  RngAuction public rngAuction;
  RNGInterface public rng;

  uint64 _auctionDuration = 3 hours;
  uint64 _rngCompletedAt = uint64(block.timestamp + 1);
  uint256 _randomNumber = 123;
  address _recipient = address(2);
  uint32 _currentSequenceId = 101;
  RngAuction.RngRequest _rngRequest =
    RngAuction.RngRequest(
      1, // rngRequestId
      uint32(block.number + 1), // lockBlock
      _currentSequenceId, // sequenceId
      0 //rngRequestedAt
    );

  function setUp() public {
    vm.warp(0);

    rngAuction = RngAuction(makeAddr("rngAuction"));
    vm.etch(address(rngAuction), "rngAuction");

    rng = RNGInterface(makeAddr("rng"));
    vm.etch(address(rng), "rng");

    drawAuction = new DrawAuctionHarness(rngAuction, _auctionDuration);
  }

  /* ============ rngAuction() ============ */

  function testRngAuction() public {
    assertEq(address(drawAuction.rngAuction()), address(rngAuction));
  }

  /* ============ completeDraw() ============ */

  function testCompleteDraw() public {
    // Warp
    vm.warp(_rngCompletedAt + _auctionDuration / 2); // reward portion will be 0.5

    // Mock Calls
    _mockRngAuction_isRngComplete(rngAuction, true);
    _mockRngAuction_currentSequenceId(rngAuction, _currentSequenceId);
    _mockRngAuction_getRngResults(rngAuction, _rngRequest, _randomNumber, _rngCompletedAt);

    // Test
    drawAuction.completeDraw(_recipient);
    assertEq(drawAuction.lastRandomNumber(), _randomNumber);
    assertEq(drawAuction.afterDrawAuctionCounter(), 1);

    // Check results
    (AuctionResults memory _auctionResults, uint32 _sequenceId) = drawAuction.getAuctionResults();
    assertEq(_sequenceId, _currentSequenceId);
    assertEq(UD2x18.unwrap(_auctionResults.rewardPortion), uint64(5e17)); // 0.5
    assertEq(_auctionResults.recipient, _recipient);
  }

  function testCompleteDraw_EmitsEvent() public {
    // Warp
    vm.warp(_rngCompletedAt + _auctionDuration / 2); // reward portion will be 0.5

    // Mock Calls
    _mockRngAuction_isRngComplete(rngAuction, true);
    _mockRngAuction_currentSequenceId(rngAuction, _currentSequenceId);
    _mockRngAuction_getRngResults(rngAuction, _rngRequest, _randomNumber, _rngCompletedAt);

    // Test
    vm.expectEmit();
    emit AuctionCompleted(
      _recipient,
      _currentSequenceId,
      _auctionDuration / 2,
      UD2x18.wrap(uint64(5e17))
    );
    drawAuction.completeDraw(_recipient);
  }

  function testCompleteDraw_RequiresAuctionNotCompleted() public {
    vm.warp(_rngCompletedAt + _auctionDuration / 2);

    // Complete draw once
    _mockRngAuction_isRngComplete(rngAuction, true);
    _mockRngAuction_currentSequenceId(rngAuction, _currentSequenceId);
    _mockRngAuction_getRngResults(rngAuction, _rngRequest, _randomNumber, _rngCompletedAt);
    drawAuction.completeDraw(_recipient);

    // Try to complete again
    _mockRngAuction_isRngComplete(rngAuction, true);
    _mockRngAuction_currentSequenceId(rngAuction, _currentSequenceId);
    _mockRngAuction_getRngResults(rngAuction, _rngRequest, _randomNumber, _rngCompletedAt);

    vm.expectRevert(abi.encodeWithSelector(DrawAlreadyCompleted.selector));
    drawAuction.completeDraw(_recipient);
  }

  function testCompleteDraw_RequiresRngCompleted() public {
    // Mock Calls
    _mockRngAuction_isRngComplete(rngAuction, false);

    // Test
    vm.expectRevert(abi.encodeWithSelector(RngNotCompleted.selector));
    drawAuction.completeDraw(address(this));
  }

  function testCompleteDraw_RequiresAuctionNotExpired() public {
    // Warp to after auction duration
    vm.warp(_rngCompletedAt + _auctionDuration + 1);

    // Mock calls
    _mockRngAuction_isRngComplete(rngAuction, true);
    _mockRngAuction_currentSequenceId(rngAuction, _currentSequenceId);
    _mockRngAuction_getRngResults(rngAuction, _rngRequest, _randomNumber, _rngCompletedAt);

    // Test
    vm.expectRevert(abi.encodeWithSelector(DrawAuctionExpired.selector));
    drawAuction.completeDraw(_recipient);
  }

  function testCompleteDraw_TwoSequences() public {
    // Warp
    vm.warp(_rngCompletedAt + _auctionDuration / 2);

    // Mock calls
    _mockRngAuction_isRngComplete(rngAuction, true);
    _mockRngAuction_currentSequenceId(rngAuction, _currentSequenceId);
    _mockRngAuction_getRngResults(rngAuction, _rngRequest, _randomNumber, _rngCompletedAt);

    // Test
    drawAuction.completeDraw(_recipient);
    (AuctionResults memory _auctionResults0, uint32 _sequenceId0) = drawAuction.getAuctionResults();
    assertEq(_sequenceId0, _currentSequenceId);
    assertEq(UD2x18.unwrap(_auctionResults0.rewardPortion), uint64(5e17)); // 0.5
    assertEq(_auctionResults0.recipient, _recipient);

    // Warp
    vm.warp(_rngCompletedAt + (_auctionDuration * 2) + (_auctionDuration / 4));

    // Mock calls for next sequence
    RngAuction.RngRequest memory _nextRngRequest = RngAuction.RngRequest(
      _rngRequest.id + 1,
      uint32(block.number),
      _currentSequenceId + 1,
      _rngRequest.requestedAt + _auctionDuration * 2
    );
    _mockRngAuction_isRngComplete(rngAuction, true);
    _mockRngAuction_currentSequenceId(rngAuction, _currentSequenceId + 1);
    _mockRngAuction_getRngResults(
      rngAuction,
      _nextRngRequest,
      _randomNumber + 1,
      _rngCompletedAt + _auctionDuration * 2
    );

    // Test
    drawAuction.completeDraw(address(this));
    (AuctionResults memory _auctionResults1, uint32 _sequenceId1) = drawAuction.getAuctionResults();
    assertEq(_sequenceId1, _currentSequenceId + 1);
    assertEq(UD2x18.unwrap(_auctionResults1.rewardPortion), uint64(25e16)); // 0.25
    assertEq(_auctionResults1.recipient, address(this));
  }

  /* ============ isAuctionComplete() ============ */

  function testIsAuctionComplete_NotComplete() public {
    // Complete draw
    vm.warp(_rngCompletedAt + _auctionDuration / 2);
    _mockRngAuction_isRngComplete(rngAuction, true);
    _mockRngAuction_currentSequenceId(rngAuction, _currentSequenceId);
    _mockRngAuction_getRngResults(rngAuction, _rngRequest, _randomNumber, _rngCompletedAt);
    drawAuction.completeDraw(_recipient);

    // Test
    _mockRngAuction_currentSequenceId(rngAuction, _currentSequenceId);
    assertEq(drawAuction.isAuctionComplete(), true);

    // Test false on next sequence
    _mockRngAuction_currentSequenceId(rngAuction, _currentSequenceId + 1);
    assertEq(drawAuction.isAuctionComplete(), false);
  }

  /* ============ isAuctionOpen() ============ */

  function testIsAuctionOpen_IsOpen() public {
    // Warp halfway through
    vm.warp(_rngCompletedAt + _auctionDuration / 2);
    _mockRngAuction_isRngComplete(rngAuction, true);
    _mockRngAuction_currentSequenceId(rngAuction, _currentSequenceId);
    _mockRngAuction_rngCompletedAt(rngAuction, _rngCompletedAt);

    // Test
    assertEq(drawAuction.isAuctionOpen(), true);
  }

  function testIsAuctionOpen_AlreadyCompleted() public {
    // Complete draw halfway through
    vm.warp(_rngCompletedAt + _auctionDuration / 2);
    _mockRngAuction_isRngComplete(rngAuction, true);
    _mockRngAuction_currentSequenceId(rngAuction, _currentSequenceId);
    _mockRngAuction_getRngResults(rngAuction, _rngRequest, _randomNumber, _rngCompletedAt);
    drawAuction.completeDraw(_recipient);

    // Mock calls
    _mockRngAuction_isRngComplete(rngAuction, true);
    _mockRngAuction_currentSequenceId(rngAuction, _currentSequenceId);
    _mockRngAuction_rngCompletedAt(rngAuction, _rngCompletedAt);

    // Test
    assertEq(drawAuction.isAuctionOpen(), false);
  }

  function testIsAuctionOpen_Expired() public {
    // Warp halfway through
    vm.warp(_rngCompletedAt + _auctionDuration + 1);
    _mockRngAuction_isRngComplete(rngAuction, true);
    _mockRngAuction_currentSequenceId(rngAuction, _currentSequenceId);
    _mockRngAuction_rngCompletedAt(rngAuction, _rngCompletedAt);

    // Test
    assertEq(drawAuction.isAuctionOpen(), false);
  }

  function testIsAuctionOpen_RngNotCompleted() public {
    _mockRngAuction_isRngComplete(rngAuction, false);

    // Test
    assertEq(drawAuction.isAuctionOpen(), false);
  }

  /* ============ elapsedTime() ============ */

  function testElapsedTime_AtStart() public {
    // Warp to beginning of auction
    vm.warp(_rngCompletedAt);
    _mockRngAuction_rngCompletedAt(rngAuction, _rngCompletedAt);

    // Test
    assertEq(drawAuction.elapsedTime(), 0);
  }

  function testElapsedTime_Halfway() public {
    // Warp to halfway point of auction
    vm.warp(_rngCompletedAt + _auctionDuration / 2);
    _mockRngAuction_rngCompletedAt(rngAuction, _rngCompletedAt);

    // Test
    assertEq(drawAuction.elapsedTime(), _auctionDuration / 2);
  }

  function testElapsedTime_AtEnd() public {
    // Warp to end of auction
    vm.warp(_rngCompletedAt + _auctionDuration);
    _mockRngAuction_rngCompletedAt(rngAuction, _rngCompletedAt);

    // Test
    assertEq(drawAuction.elapsedTime(), _auctionDuration);
  }

  function testElapsedTime_PastAuction() public {
    // Warp past auction
    vm.warp(_rngCompletedAt + _auctionDuration + 1);
    _mockRngAuction_rngCompletedAt(rngAuction, _rngCompletedAt);

    // Test
    assertEq(drawAuction.elapsedTime(), _auctionDuration + 1);
  }

  /* ============ auctionDuration() ============ */

  function testAuctionDuration() public {
    assertEq(drawAuction.auctionDuration(), _auctionDuration);
  }

  /* ============ currentRewardPortion() ============ */

  function testCurrentRewardPortion_AtStart() public {
    // Warp to beginning of auction
    vm.warp(_rngCompletedAt);
    _mockRngAuction_rngCompletedAt(rngAuction, _rngCompletedAt);

    // Test
    assertEq(UD2x18.unwrap(drawAuction.currentRewardPortion()), 0); // 0.0
  }

  function testCurrentRewardPortion_Halfway() public {
    // Warp to halfway point of auction
    vm.warp(_rngCompletedAt + _auctionDuration / 2);
    _mockRngAuction_rngCompletedAt(rngAuction, _rngCompletedAt);

    // Test
    assertEq(UD2x18.unwrap(drawAuction.currentRewardPortion()), 5e17); // 0.5
  }

  function testCurrentRewardPortion_AtEnd() public {
    // Warp to end of auction
    vm.warp(_rngCompletedAt + _auctionDuration);
    _mockRngAuction_rngCompletedAt(rngAuction, _rngCompletedAt);

    // Test
    assertEq(UD2x18.unwrap(drawAuction.currentRewardPortion()), 1e18); // 1.0
  }

  function testCurrentRewardPortion_PastAuction() public {
    // Warp past auction
    vm.warp(_rngCompletedAt + _auctionDuration + _auctionDuration / 10);
    _mockRngAuction_rngCompletedAt(rngAuction, _rngCompletedAt);

    // Test
    assertEq(UD2x18.unwrap(drawAuction.currentRewardPortion()), 11e17); // 1.1
  }

  /* ============ getAuctionResults() ============ */

  function testGetAuctionResults() public {
    // Complete draw halfway through
    vm.warp(_rngCompletedAt + _auctionDuration / 2);
    _mockRngAuction_isRngComplete(rngAuction, true);
    _mockRngAuction_currentSequenceId(rngAuction, _currentSequenceId);
    _mockRngAuction_getRngResults(rngAuction, _rngRequest, _randomNumber, _rngCompletedAt);
    drawAuction.completeDraw(_recipient);

    // Tests
    (AuctionResults memory _auctionResults, uint32 _sequenceId) = drawAuction.getAuctionResults();

    assertEq(_sequenceId, _currentSequenceId);
    assertEq(_auctionResults.recipient, _recipient);
    assertEq(UD2x18.unwrap(_auctionResults.rewardPortion), 5e17);
  }
}
