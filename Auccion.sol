// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract Auction is Ownable, ReentrancyGuard, Pausable {
    uint private deadline;
    uint private constant commissionPercent = 2; // 2% commission
    uint private constant timeExtension = 10 minutes;
    bool private ended;

    struct Bid {
        address bidder;
        uint amount;
    }

    Bid private highestBid;
    mapping(address => uint) private accumulatedBids;
    mapping(address => uint[]) private userBidHistory;
    mapping(address => uint) public refundableBalances;

    event NewBid(address indexed bidder, uint amount);
    event AuctionEnded(address winner, uint winningAmount);
    event FundsWithdrawn(address indexed user, uint amountWithdrawn, uint commissionRetained);
    // Emitted when non-winning bids are prepared for refund
    event BidRefundPrepared(address indexed bidder, uint refundableAmount, uint fee);
    // Emitted when a bidder withdraws excess funds during the auction
    event PartialRefundProcessed(address indexed bidder, uint amount);
    event EmergencyWithdrawal(address indexed receiver, uint amount);

    // Ensures the auction is still active.
    modifier onlyBeforeEnd() {
        require(block.timestamp < deadline, "Auction: Auction has ended");
        _;
    }

    // Sets the auction duration when the contract is deployed.
    constructor(uint _durationSeconds) Ownable(msg.sender) {
        deadline = block.timestamp + _durationSeconds;
    }

    // Allows the contract owner to pause the auction.
    function pauseAuction() external onlyOwner {
        _pause();
    }

    // Allows the contract owner to unpause the auction.
    function unpauseAuction() external onlyOwner {
        _unpause();
    }

    // Allows users to place a bid, updating the highest bid and extending the deadline if needed.
    function placeBid() external payable nonReentrant whenNotPaused onlyBeforeEnd {
        require(msg.value > 0, "Auction: Bid must be > 0");

        uint currentTotalBid = accumulatedBids[msg.sender];
        uint newTotalBid = currentTotalBid + msg.value;

        if (highestBid.amount == 0) {
            accumulatedBids[msg.sender] = newTotalBid;
            userBidHistory[msg.sender].push(msg.value);
            highestBid = Bid(msg.sender, newTotalBid);
            emit NewBid(msg.sender, newTotalBid);
            return;
        }

        uint minRequiredBid = highestBid.amount + (highestBid.amount * 5) / 100;
        require(newTotalBid > minRequiredBid, "Auction: New accumulated bid must be 5% higher than current highest");

        uint previousHighestAmount = highestBid.amount;

        accumulatedBids[msg.sender] = newTotalBid;
        userBidHistory[msg.sender].push(msg.value);

        if (newTotalBid > previousHighestAmount) {
            highestBid = Bid(msg.sender, newTotalBid);
            if (deadline - block.timestamp <= timeExtension) {
                deadline += timeExtension;
            }
        }
        
        emit NewBid(msg.sender, newTotalBid);
    }

    // Finalizes the auction, determines the winner, and prepares their payout. Callable only by owner after deadline.
    function endAuction() external onlyOwner nonReentrant {
        require(block.timestamp >= deadline, "Auction: Auction not ended yet");
        require(!ended, "Auction: Auction already ended");
        require(highestBid.amount > 0, "Auction: No bids placed");

        ended = true;

        uint winnerCommission = (highestBid.amount * commissionPercent) / 100;
        uint winnerPayout = highestBid.amount - winnerCommission;
        refundableBalances[highestBid.bidder] += winnerPayout;

        emit AuctionEnded(highestBid.bidder, highestBid.amount);
    }

    // Allows any participant to withdraw their refundable deposit after the auction ends.
    function retDeposit() external nonReentrant returns (bool success) {
        require(ended, "Auction: Auction not ended");
        uint amountToWithdraw = refundableBalances[msg.sender];
        require(amountToWithdraw > 0, "Auction: No refundable deposit available");

        refundableBalances[msg.sender] = 0;
        (success, ) = payable(msg.sender).call{value: amountToWithdraw}("");
        require(success, "Auction: Transfer failed");

        uint commissionRetained = (amountToWithdraw * commissionPercent) / (100 - commissionPercent);
        emit FundsWithdrawn(msg.sender, amountToWithdraw, commissionRetained);
        return true;
    }

    // Allows bidders to withdraw excess funds sent during the auction, if they are not the current highest bidder.
    function partialRefund() external nonReentrant whenNotPaused onlyBeforeEnd returns (bool success) {
        require(msg.sender != highestBid.bidder, "Auction: Current highest bidder cannot withdraw excess");
        
        uint currentRequired = highestBid.amount + (highestBid.amount * 5) / 100;
        uint accumulatedTotal = accumulatedBids[msg.sender];
        require(accumulatedTotal > currentRequired, "Auction: No excess funds available for partial refund");

        uint excessAmount = accumulatedTotal - currentRequired;
        
        accumulatedBids[msg.sender] = currentRequired;

        (success, ) = payable(msg.sender).call{value: excessAmount}("");
        require(success, "Auction: Transfer of partial refund failed");

        emit PartialRefundProcessed(msg.sender, excessAmount);
        return true;
    }

    // Allows the contract owner to withdraw all funds in an emergency after the auction has ended.
    function emergencyWithdraw() external onlyOwner nonReentrant {
        require(ended, "Auction: Auction not ended");
        
        uint contractBalance = address(this).balance;
        require(contractBalance > 0, "Auction: No funds to withdraw in emergency");
        payable(owner()).transfer(contractBalance);

        emit EmergencyWithdrawal(owner(), contractBalance);
    }

    // --- View Functions ---

    // Returns the current highest bid details (bidder address and amount).
    function getHighestBid() external view returns (address bidder, uint amount) {
        return (highestBid.bidder, highestBid.amount);
    }

    // Returns the history of individual bids made by a specific user.
    function bidsOf(address user) external view returns (uint[] memory userBids) {
        return userBidHistory[user];
    }

    // Returns the remaining time until the auction deadline (0 if ended).
    function timeRemaining() external view returns (uint remainingTime) {
        if (block.timestamp >= deadline) return 0;
        return deadline - block.timestamp;
    }

    // Returns the timestamp of the auction's deadline.
    function getDeadline() external view returns (uint auctionDeadline) {
        return deadline;
    }

    // Returns true if the auction has ended, false otherwise.
    function isEnded() external view returns (bool endedStatus) {
        return ended;
    }

    // Returns the total accumulated bid amount for a specific user.
    function totalBidOf(address user) external view returns (uint totalBidAmount) {
        return accumulatedBids[user];
    }

    // Returns the constant commission percentage applied to bids.
    function getCommissionPercent() external pure returns (uint) {
        return commissionPercent;
    }
}
