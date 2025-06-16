# Auction Smart Contract

This Solidity smart contract implements a decentralized auction system on the blockchain. Its design and functionalities comply with the specified requirements for managing bids, determining the winner, handling funds, and processing refunds.

---

## Contract Functionalities

* **Constructor (`constructor`)**
    * **Action:** Initializes the auction contract upon deployment.
    * **Variables:** Sets the initial auction duration and designates the deployer as the contract owner.

* **Place Bid Function (`placeBid`)**
    * **Action:** Allows participants to send Ether to place a bid on the item.
    * **Bid Validation:**
        * Requires the bid amount to be greater than zero.
        * Validates that the bid is at least 5% higher than the current highest bid.
        * Ensures the bid is placed while the auction is active.
        * Verifies that the number of **new unique bidders** has not exceeded the `MAX_BIDDERS` limit. Existing bidders can always increase their bids.
    * **Deadline Extension:** If a valid bid is placed within the last 10 minutes of the auction, the deadline is automatically extended by 10 additional minutes.
    * **Registration:** Bids are deposited into the contract and associated with the bidder's address, also registering unique bidders.

* **End Auction Function (`endAuction`)**
    * **Action:** Concludes the auction once its deadline has passed.
    * **Winner Determination:** Identifies the highest bidder as the winner.
    * **Deposit Refund:** Iterates over all bidders (winner and non-winners) and automatically transfers their deposits (minus the commission) back to their respective addresses.
    * **Authorization:** Can only be called by the owner once the auction has ended and has not been previously finalized.

* **Partial Refund Function (`partialRefund`)**
    * **Action:** Allows participants to withdraw excess Ether sent during the auction while it is still active. A 2% commission is applied to the withdrawn amount.
    * **Conditions:** Applicable only if the caller is not the current highest bidder and has excess funds in the contract.

* **Retrieve Deposit Function (`retDeposit`)**
    * **Action:** Allows a user to withdraw their funds. A 2% commission is applied to the withdrawn amount.
    * **Usage:** Primarily for pending balances that were not automatically transferred for any reason.

* **Emergency Withdrawal Function (`emergencyWithdraw`)**
    * **Action:** Allows the contract owner to withdraw the entire Ether balance from the contract in an emergency.
    * **Conditions:** Can only be executed once the auction has ended.

* **Pause Auction Control (`pauseAuction`)**
    * **Action:** Allows the owner to temporarily suspend the ability to place new bids.

* **Unpause Auction Control (`unpauseAuction`)**
    * **Action:** Allows the owner to resume the auction, re-enabling bids.

---

## State Variables

* `deadline`: Timestamp of the auction's end.
* `COMMISSION_PERCENT`: Percentage commission applied to each withdrawal.
* `TIME_EXTENSION`: Duration of the auction deadline extension.
* `ended`: Boolean indicator if the auction has concluded.
* `MAX_BIDDERS`: Maximum limit for unique bidders allowed.
* `highestBid`: Structure storing the address and amount of the highest bid.
* `accumulatedBids`: Mapping of bidder addresses to their total accumulated bid amount.
* `userBidHistory`: Mapping of bidder addresses to an array of their individual bids.
* `refundableBalances`: Mapping of addresses to pending refund amounts.
* `allUniqueBidders`: Array of all unique bidder addresses.
* `hasBidded`: Auxiliary mapping to verify bidder uniqueness.

---

## Events

* `NewBid(address indexed bidder, uint amount)`: Emitted when a new bid is placed.
* `AuctionEnded(address winner, uint winningAmount)`: Emitted when the auction ends.
* `FundsWithdrawn(address indexed user, uint amountWithdrawn, uint commissionRetained)`: Emitted when funds are withdrawn.
* `NonWinnerRefunded(address indexed bidder, uint originalAmount, uint netAmount, uint commissionAmount)`: Emitted for each automatic refund to a non-winner.
* `PartialRefundProcessed(address indexed bidder, uint originalAmount, uint netAmount, uint commissionAmount)`: Emitted when a partial refund is processed.
* `EmergencyWithdrawal(address indexed receiver, uint amount)`: Emitted when the owner performs an emergency withdrawal.

---

## View Functions (Read-Only)

* `getHighestBid()`: Returns the current highest bidder and their bid amount.
* `showAllBids()`: Returns a complete list of all unique bidders and their total accumulated bid amounts.
* `bidsOf(address user)`: Returns a user's history of individual bids.
* `timeRemaining()`: Calculates and returns the time left until the auction deadline.
* `getDeadline()`: Returns the auction's deadline timestamp.
* `isEnded()`: Checks if the auction has concluded.
* `totalBidOf(address user)`: Returns the total accumulated bid amount for a user.
* `getCommissionPercent()`: Returns the commission percentage.
* `getAllUniqueBidders()`: Returns the list of all unique bidder addresses.
* `getMaxBidders()`: Returns the maximum limit of bidders.
