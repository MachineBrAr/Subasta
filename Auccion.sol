// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title Auction
 * @dev Smart contract implementing a decentralized auction system.
 * Manages bidding, fund allocation, winner determination, and refunds.
 */
contract Auction is Ownable, ReentrancyGuard, Pausable {
    /// @dev The exact timestamp when the auction is scheduled to end.
    uint private deadline;
    /// @dev The commission percentage (2%) applied to each withdrawal.
    uint private constant COMMISSION_PERCENT = 2;
    /// @dev The time extension (10 minutes) added to the deadline for last-minute bids.
    uint private constant TIME_EXTENSION = 10 minutes;
    /// @dev A boolean indicator stating whether the auction has officially ended.
    bool private ended;

    /// @dev Maximum limit for unique bidders allowed in the auction.
    uint private constant MAX_BIDDERS = 100;

    /// @dev Structure to represent a bid, storing the bidder's address and their total bid amount.
    struct Bid {
        address bidder;
        uint amount;
    }

    /// @dev Stores the details of the current highest bid.
    Bid private highestBid;
    /// @dev Maps bidder addresses to their total accumulated bid amount.
    mapping(address => uint) private accumulatedBids;
    /// @dev Maps bidder addresses to an array of their individual bid amounts, maintaining a history.
    mapping(address => uint[]) private userBidHistory;
    /// @dev Stores the net amount to be paid to the winner.
    mapping(address => uint) public refundableBalances; // Public for visibility, used internally for winner

    /// @dev Array storing all unique addresses that have placed a bid.
    address[] private allUniqueBidders;
    /// @dev Auxiliary mapping to check if an address has already been added to allUniqueBidders, preventing duplicates.
    mapping(address => bool) private hasBidded;

    /// @dev Emitted when a new bid is successfully placed.
    /// @param bidder The address of the bidder.
    /// @param amount The new total accumulated bid amount of the bidder.
    event NewBid(address indexed bidder, uint amount);
    /// @dev Emitted when the auction officially concludes.
    /// @param winner The address of the winning bidder.
    /// @param winningAmount The total winning bid amount.
    event AuctionEnded(address winner, uint winningAmount);
    /// @dev Emitted when a user successfully withdraws funds.
    /// @param user The address of the user who withdrew the funds.
    /// @param amountWithdrawn The amount of Ether withdrawn.
    /// @param commissionRetained The commission retained from the payment.
    event FundsWithdrawn(address indexed user, uint amountWithdrawn, uint commissionRetained);
    /// @dev Emitted when a deposit is automatically refunded to a non-winning bidder.
    /// @param bidder The address of the bidder who received the refund.
    /// @param originalAmount The original amount of Ether before commission.
    /// @param netAmount The net amount of Ether refunded after commission.
    /// @param commissionAmount The commission retained.
    event NonWinnerRefunded(address indexed bidder, uint originalAmount, uint netAmount, uint commissionAmount);
    /// @dev Emitted when a bidder successfully withdraws excess funds during the auction.
    /// @param bidder The address of the bidder who withdrew excess funds.
    /// @param originalAmount The original amount of Ether before commission.
    /// @param netAmount The net amount of Ether withdrawn after commission.
    /// @param commissionAmount The commission retained.
    event PartialRefundProcessed(address indexed bidder, uint originalAmount, uint netAmount, uint commissionAmount);
    /// @dev Emitted when the contract owner performs an emergency withdrawal.
    /// @param receiver The address receiving the withdrawn funds (contract owner).
    /// @param amount The total balance withdrawn from the contract.
    event EmergencyWithdrawal(address indexed receiver, uint amount);

    /**
     * @dev Modifier to ensure a function can only be called while the auction is active.
     */
    modifier onlyBeforeEnd() {
        require(block.timestamp < deadline, "Auction ended");
        _;
    }

    /**
     * @dev Constructor for initializing the auction contract.
     * @param _durationSeconds The initial duration of the auction in seconds.
     */
    constructor(uint _durationSeconds) Ownable(msg.sender) {
        deadline = block.timestamp + _durationSeconds;
    }

    /**
     * @dev Allows the contract owner to pause the auction.
     * Inherited from OpenZeppelin's Pausable.
     */
    function pauseAuction() external onlyOwner {
        _pause();
    }

    /**
     * @dev Allows the contract owner to unpause the auction.
     * Inherited from OpenZeppelin's Pausable.
     */
    function unpauseAuction() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Allows users to place a bid by sending Ether.
     * A bid is valid if:
     * - It is greater than 0.
     * - It is at least 5% higher than the current highest bid (or the first bid).
     * - It is placed while the auction is active.
     * - The number of unique bidders has not exceeded the maximum limit.
     * If a new valid bid is placed within the last 10 minutes,
     * the auction deadline is extended by 10 more minutes.
     */
    function placeBid() external payable nonReentrant whenNotPaused onlyBeforeEnd {
        require(msg.value > 0, "Bid > 0");

        uint currentTotalBid = accumulatedBids[msg.sender];
        uint newTotalBid = currentTotalBid + msg.value;

        // Register bidder if new and check bidder limit for new participants only.
        if (!hasBidded[msg.sender]) {
            require(allUniqueBidders.length < MAX_BIDDERS, "Max bidders reached");
            hasBidded[msg.sender] = true;
            allUniqueBidders.push(msg.sender);
        }

        // Determine if it's the first bid or if the new bid is the highest.
        if (highestBid.amount == 0) {
            accumulatedBids[msg.sender] = newTotalBid;
            userBidHistory[msg.sender].push(msg.value);
            highestBid = Bid(msg.sender, newTotalBid);
            emit NewBid(msg.sender, newTotalBid);
            return;
        }

        // Validate that the new accumulated bid exceeds 5% of the current highest bid.
        uint minRequiredBid = highestBid.amount + (highestBid.amount * 5) / 100;
        require(newTotalBid > minRequiredBid, "Bid too low");

        // Update bid state.
        accumulatedBids[msg.sender] = newTotalBid;
        userBidHistory[msg.sender].push(msg.value);

        // Update highest bid if applicable and extend deadline for last-minute bids.
        if (newTotalBid > highestBid.amount) {
            highestBid = Bid(msg.sender, newTotalBid);
            if (deadline - block.timestamp <= TIME_EXTENSION) {
                deadline += TIME_EXTENSION;
            }
        }
        emit NewBid(msg.sender, newTotalBid);
    }

    /**
     * @dev Ends the auction once its deadline has passed.
     * Determines the winner, calculates their payout (with a 2% commission), and performs payments.
     * Automatically refunds deposits to all bidders (winner and non-winners).
     * Can only be called by the owner when the auction has ended and not been previously finalized.
     */
    function endAuction() external onlyOwner nonReentrant {
        require(block.timestamp >= deadline, "Not ended");
        require(!ended, "Already ended");
        require(highestBid.amount > 0, "No bids");

        // Mark the auction as ended.
        ended = true;

        // Declare local variables outside the loop for efficiency.
        uint uniqueBiddersCount = allUniqueBidders.length;
        address currentBidder;
        uint amountToProcess;
        uint commissionAmount;
        uint netAmount;
        bool success;

        // Iterate over all registered bidders to process automatic refunds/payments.
        for (uint i = 0; i < uniqueBiddersCount; i++) {
            currentBidder = allUniqueBidders[i];
            amountToProcess = accumulatedBids[currentBidder];

            if (amountToProcess > 0) { // Only process if funds exist
                commissionAmount = (amountToProcess * COMMISSION_PERCENT) / 100;
                netAmount = amountToProcess - commissionAmount;

                accumulatedBids[currentBidder] = 0; // Mark funds as processed before transfer.

                (success, ) = payable(currentBidder).call{value: netAmount}("");
                require(success, "Fund transfer failed");

                if (currentBidder == highestBid.bidder) {
                    emit FundsWithdrawn(currentBidder, netAmount, commissionAmount);
                } else {
                    emit NonWinnerRefunded(currentBidder, amountToProcess, netAmount, commissionAmount);
                }
            }
        }

        // Final check for any remaining winner balance in refundableBalances.
        // This scenario is unlikely if allUniqueBidders properly includes the winner and accumulatedBids is correctly updated.
        if (refundableBalances[highestBid.bidder] > 0) {
            uint remainingWinnerBalance = refundableBalances[highestBid.bidder];
            commissionAmount = (remainingWinnerBalance * COMMISSION_PERCENT) / 100;
            netAmount = remainingWinnerBalance - commissionAmount;
            refundableBalances[highestBid.bidder] = 0;
            (success, ) = payable(highestBid.bidder).call{value: netAmount}("");
            require(success, "Remaining winner transfer failed");
            emit FundsWithdrawn(highestBid.bidder, netAmount, commissionAmount);
        }

        // Emit auction ended event.
        emit AuctionEnded(highestBid.bidder, highestBid.amount);
    }

    /**
     * @dev Allows a user to withdraw their funds.
     * A 2% commission will be applied to the withdrawn amount.
     * @return success True if the withdrawal was successful.
     */
    function retDeposit() external nonReentrant returns (bool success) {
        require(ended, "Auction not ended");
        
        // Declare local variables.
        uint amountToProcess = accumulatedBids[msg.sender];
        require(amountToProcess > 0, "No funds pending withdrawal");
        
        uint commissionAmount = (amountToProcess * COMMISSION_PERCENT) / 100;
        uint netAmount = amountToProcess - commissionAmount;

        accumulatedBids[msg.sender] = 0; // Clear the balance before transfer.
        
        // Transfer the Ether.
        (success, ) = payable(msg.sender).call{value: netAmount}("");
        require(success, "Transfer failed");

        emit FundsWithdrawn(msg.sender, netAmount, commissionAmount);
        return true;
    }

    /**
     * @dev Allows bidders to withdraw excess funds sent during the auction, before it ends.
     * A 2% commission will be applied to the withdrawn amount.
     * Can only be called by bidders who are not the highest bidder and have sent more than required.
     * @return success True if the partial refund was successful.
     */
    function partialRefund() external nonReentrant whenNotPaused onlyBeforeEnd returns (bool success) {
        require(msg.sender != highestBid.bidder, "Cannot refund highest");
        
        // Declare local variables.
        uint currentRequired = highestBid.amount + (highestBid.amount * 5) / 100;
        uint accumulatedTotal = accumulatedBids[msg.sender];
        require(accumulatedTotal > currentRequired, "No excess funds");

        // Calculate the excess and update the accumulated balance.
        uint originalExcessAmount = accumulatedTotal - currentRequired;
        
        uint commissionAmount = (originalExcessAmount * COMMISSION_PERCENT) / 100;
        uint netExcessAmount = originalExcessAmount - commissionAmount;

        accumulatedBids[msg.sender] = currentRequired; // Keep only the required amount.

        // Perform the excess transfer.
        (success, ) = payable(msg.sender).call{value: netExcessAmount}("");
        require(success, "Partial refund failed");

        emit PartialRefundProcessed(msg.sender, originalExcessAmount, netExcessAmount, commissionAmount);
        return true;
    }

    /**
     * @dev Allows the contract owner to withdraw the entire contract balance in an emergency.
     * Can only be called after the auction has ended.
     */
    function emergencyWithdraw() external onlyOwner nonReentrant {
        require(ended, "Auction not ended");
        
        uint contractBalance = address(this).balance;
        require(contractBalance > 0, "No funds to withdraw");
        
        // Transfer the entire contract balance to the owner.
        payable(owner()).transfer(contractBalance);

        emit EmergencyWithdrawal(owner(), contractBalance);
    }

    // --- View Functions (Do not modify state) ---

    /**
     * @dev Returns the details of the current highest bid.
     * @return bidder The address of the current highest bidder.
     * @return amount The amount of the current highest bid.
     */
    function getHighestBid() external view returns (address bidder, uint amount) {
        return (highestBid.bidder, highestBid.amount);
    }

    /**
     * @dev Returns the complete list of all unique bidders with their total accumulated bid amounts.
     * This function provides a convenient way to retrieve all bidding data in a single call.
     * @return bidders Array of unique bidder addresses.
     * @return amounts Array of corresponding total bid amounts for each unique bidder.
     */
    function showAllBids() external view returns (address[] memory bidders, uint[] memory amounts) {
        uint biddersCount = allUniqueBidders.length;
        bidders = new address[](biddersCount);
        amounts = new uint[](biddersCount);
        
        for (uint i = 0; i < biddersCount; i++) {
            bidders[i] = allUniqueBidders[i];
            amounts[i] = accumulatedBids[allUniqueBidders[i]];
        }
        
        return (bidders, amounts);
    }

    /**
     * @dev Returns the history of individual bid amounts for a specific user.
     * @param user The address of the user to query.
     * @return userBids An array of individual bid amounts made by the user.
     */
    function bidsOf(address user) external view returns (uint[] memory userBids) {
        return userBidHistory[user];
    }

    /**
     * @dev Calculates and returns the time remaining until the auction deadline.
     * @return remainingTime The remaining time in seconds, or 0 if the auction has ended.
     */
    function timeRemaining() external view returns (uint remainingTime) {
        if (block.timestamp >= deadline) return 0;
        return deadline - block.timestamp;
    }

    /**
     * @dev Returns the exact timestamp of the auction deadline.
     * @return auctionDeadline The timestamp when the auction is scheduled to end.
     */
    function getDeadline() external view returns (uint auctionDeadline) {
        return deadline;
    }

    /**
     * @dev Checks if the auction has officially concluded.
     * @return endedStatus True if the auction has ended, false otherwise.
     */
    function isEnded() external view returns (bool endedStatus) {
        return ended;
    }

    /**
     * @dev Returns the total accumulated bid amount for a specific user.
     * @param user The address of the user to query.
     * @return totalBidAmount The total sum of bids accumulated by the user.
     */
    function totalBidOf(address user) external view returns (uint totalBidAmount) {
        return accumulatedBids[user];
    }

    /**
     * @dev Returns the constant commission percentage applied to withdrawals.
     * @return commissionPercent The commission rate (e.g., 2 for 2%).
     */
    function getCommissionPercent() external pure returns (uint) {
        return COMMISSION_PERCENT;
    }

    /**
     * @dev Returns the list of all unique bidders who have participated.
     * @return allBiddersList An array of all unique bidder addresses.
     */
    function getAllUniqueBidders() external view returns (address[] memory allBiddersList) {
        return allUniqueBidders;
    }

    /**
     * @dev Returns the maximum limit of bidders allowed in the auction.
     * @return maxBidders The maximum number of bidders.
     */
    function getMaxBidders() external pure returns (uint) {
        return MAX_BIDDERS;
    }
}
