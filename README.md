# Smart Auction Contract

This Solidity smart contract implements a decentralized auction system on the blockchain. Its main purpose is to manage the bidding process, fund allocation, and winner determination in an automated and transparent manner.

---

## Core Functionality

* **Initial Configuration:** The contract is initialized with a specific duration for the auction and establishes the deployer as its owner, who will have administrative controls.
* **Auction Management:**
* **Pause and Resume:** The contract owner has the ability to pause the auction at any time to stop bidding activities and resume it when necessary.
    * **Bidding:** Participants can send Ether to the contract to place their bids. Each new bid must be at least 5% higher than the current highest bid.
    * **Extension of Deadline for Late Bids:** If a new highest bid is placed in the last 10 minutes before the auction deadline, the deadline is automatically extended by an additional 10 minutes to maintain fair competition.
    * **Auction Completion:** Once the deadline has expired, the contract owner can end the auction. This action identifies the highest bidder as the winner and prepares their payment, deducting a 2% commission.
* **Fund Management:**
    * **Withdrawal of Refundable Deposits:** After the auction has concluded, both the winner and the non-winning bidders can withdraw their respective funds. The winner receives their payment after the commission, while the non-winners can claim their total accumulated funds. This withdrawal mechanism requires users to initiate the transaction for added security.
    * **Partial Refunds During the Auction:** Bidders who do not have the highest bid at any given time can withdraw any amount of Ether they have submitted above the minimum bid required, thus recovering unused funds while the auction is still active.
    * **Emergency Withdrawal:** In critical situations and only after the auction has ended, the contract owner can withdraw all remaining funds from the contract.

---

## Status Query

The contract provides read-only functions that allow anyone to query its current status without incurring gas costs:

* Obtain details of the **current highest bid** (bidder address and amount).
* Access the **history of individual bids** made by a specific user address.
* Determine the **time remaining** until the auction ends.
* Query the **exact timestamp of the auction deadline**.
* Verify whether the **auction has officially ended**.
* Obtain the **total amount of accumulated bids** for any user.
* Query the **commission percentage** applied to bids.

Translated with DeepL.com (free version)
