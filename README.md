# Rocket Lend

Rocket Lend is a protocol for lending/borrowing RPL to stake on Rocket Pool
nodes.

No collateral asset is required to borrow RPL from lenders because the borrowed
RPL is immediately staked on a node, and the withdrawal address for the node is
verified to be the Rocket Lend smart contract that will enforce the terms of
the loan. Another way to think of it is that the collateral for the loan is the
node's staked assets (ETH and RPL).

## Technical Design

Rocket Lend consists of a single immutable smart contract ("the (Rocket Lend)
contract"), used for all interaction with the protocol and designed to be the
primary and RPL withdrawal address for Rocket Pool nodes that borrow RPL from
the protocol.

The protocol participants come in two types: "lenders", who supply RPL to the
protocol, and "borrowers" who borrow RPL from the protocol to stake on Rocket
Pool nodes.

A lender is assigned a unique identifier when they register with Rocket Lend.
They provide a withdrawal address (to which funds from the protocol will be
sent), which can be changed.

A borrower is identified by the Rocket Pool node they are borrowing for. They
also have a withdrawal address, which can be changed, to which their funds are
ultimately sent.

### Lending Pools

The contract manages pools of RPL that are made available by lenders to be used
by borrowers. There may be many pools active at once. Each lender may have any
number of pools.

Although each pool has a single lender, the relationship between borrowers and
pools is many to many. A given pool may lend RPL to many borrowers, and a given
borrower may borrow RPL from many pools.

In return for providing RPL to be staked, lenders expect to receive interest.
The interest rate is specified by the lender when the pool is created. It is
charged on RPL that is actually borrowed, for the time during the loan term
that it is borrowed. The lender also expects to eventually be repaid the RPL
they supplied to a lending pool.

Each pool is identified by the following parameters:
- Lender: the identifier for the lender, who receives repaid RPL and interest.
- Interest rate: the number of attoRPL per second per RPL that has been
  borrowed and not yet repaid, charged as interest to the borrower.
- End time: the time by which the lender wishes the pool's RPL to be repaid.
  Before this time, interest is charged on borrowed RPL. After this time, any
  outstanding debt (including interest) can be seized by the lender from any of
  the borrower's RPL or ETH as it is withdrawn.

RPL may be supplied to a pool (without changing its parameters) at any time.
RPL that is not currently borrowed may be withdrawn from the pool at any time.

Lending pools can be restricted to a limited set of borrowers. The set of
borrowers that are allowed to borrow from a pool can be changed at any time by
the lender (without changing the parameters that identify the pool).

### Borrower Actions

Borrowers can use the Rocket Lend contract to:

- Register as a borrower in the protocol by confirming their node's primary and
  RPL withdrawal addresses as the Rocket Lend contract
- Stake RPL from a pool onto their node
- Repay a pool by withdrawing RPL from their node
- Repay a pool by supplying fresh RPL - this may also be done by a third party
  on the borrower's behalf
- Transfer their debt from one pool to another - if the new pool has the same
  lender, this can be done up to the lender's allowance for transfers without
  requiring available funds in the new pool
- Withdraw excess RPL (after repaying any debt) from their node to their
  withdrawal address
- Withdraw ETH rewards from their node to their withdrawal address
- Withdraw unstaked ETH from their node to their withdrawal address
- Change their (Rocket Lend) withdrawal address
- Exit Rocket Lend by changing their node's primary and RPL withdrawal addresses

#### Borrow Limit

The total amount borrowed by a borrower is limited by the ETH staked on their
node. This reduces the incentive for a node operator to lock up borrowed RPL
with no intention of ever using it.

The borrow limit is 30% of the value of the following: ETH bonded to currently
active minipools plus ETH supplied (via stake on behalf) for creating new
minipools. It is denominated in RPL using the RPL price from Rocket Pool at the
time RPL is being borrowed.

Rewards and withdrawn funds are not included, so if a borrower reaches their
borrow limit they should claim and restake these funds to be able to borrow
more.

TODO: discuss motivation for borrow limit and choice of percentage

### Lender Actions

Lenders can use the Rocket Lend contract to:

- Register as a lender in the protocol by claiming a new identifier
- Transfer control (ownership of funds) of their lender identifier to a new
  address
- Create a new lending pool with their chosen parameters
- Restrict or expand the set of borrowers that are allowed to borrow RPL from
  one of their lending pools
- Supply RPL to one of their lending pools - this may also be done by a third
  party on the lender's behalf
- Set the allowance for transfers of debt into one of their lending pools
- Withdraw RPL that is not currently borrowed from one of their lending pools
- Withdraw any interest paid to one of their lending pools, and optionally supply it back to the pool
- Withdraw any remaining debt (borrowed RPL plus interest) from a node after
  the end time of the lending pool
- Force a claim/withdrawal of ETH or RPL from any borrower that has defaulted
  on a loan from one of the lender's pools, up to the outstanding debt amount

### Defaults

TODO: how defaulting is assessed and repaid
TODO: how RPL slashing might affect a default

## Contract API

### Constants

Most of these are explicit limits on dynamically sized types (as required by
Vyper), chosen to be large enough to be practically unlimited.

| Name                  | Value   | Note                 |
|-----------------------|---------|----------------------|
|`MAX_TOTAL_INTERVALS`  |    2048 | 170+ years           |
|`MAX_CLAIM_INTERVALS`  |     128 | ~ 10 years           |
|`MAX_PROOF_LENGTH`     |      32 | ~ 4 billion claimers |
|`MAX_NODE_MINIPOOLS`   |    2048 |                      |
|`MAX_ADDRESS_BATCH`    |    2048 |                      |
|`BORROW_LIMIT_PERCENT` |      30 |                      |

### Structs

- `PoolParams` (per pool id)
  - `lender`: identifier (non-negative integer) of the pool owner
  - `interestRate`: attoRPL (i.e. RPL wei) per RPL borrowed per second (before the loan end time)
  - `endTime`: seconds after the Unix epoch when the loan ends

- `PoolState` (per pool id)
  - `available`: amount of RPL available to be borrowed or returned to the lender
  - `borrowed`: amount of RPL currently borrowed
  - `allowance`: limit on how much RPL can be made available by transferring either borrowed RPL from another of the lender's pools, or interest from another of the lender's loans
  - `interestPaid`: interest the pool has accrued (available to be claimed by the lender)
  - `reclaimed`: amount of ETH accrued in service of defaults (available to be claimed by the lender)

- `LoanState` (per pool id and node (borrower))
  - `borrowed`: amount of RPL currently borrowed in this loan
  - `startTime`: start time for ongoing interest accumulation on the `borrowed` amount
  - `interestDue`: interest due (accrued before `startTime`) but not yet paid by the borrower

- `BorrowerState` (per node)
  - `borrowed`: total RPL borrowed
  - `interestDue`: interest due, not including ongoing interest on `borrowed`, but not yet paid
  - `RPL`: amount of RPL available for (with priority) debt repayments or to be withdrawn
  - `ETH`: amount of ETH available for (with priority) debt repayments on liquidation or to be withdrawn
  - `index`: first not-yet-accounted-for Rocket Pool rewards interval index
  - `address`: current (Rocket Lend) withdrawal address for the borrower
  - `pending`: pending address used when changing the borrower address

### Views

- `nextLenderId() → uint256`: the first unassigned lender identifier
- `params(id: bytes32) → PoolParams`
- `pools(id: bytes32) → PoolState`
- `loans(id: bytes32, node: address) → LoanState`
- `allowedToBorrow(id: bytes32, node: address) → bool`: if the null address is allowed, anyone is
- `borrowers(node: address) → BorrowerState`
- `intervals(node: address, index: uint256) → bool`: whether a rewards interval index is known to be claimed
- `lenderAddress(lender: uint256) → address`
- `pendingLenderAddress(lender: uint256) → address`
- `rocketStorage() → address`: the address of the Rocket Storage contract
- `RPL() → address`: the address of the RPL token contract

### Lender functions
- `registerLender() → uint256`
- `changeLenderAddress(_lender: uint256, _newAddress: address, _confirm: bool)`
- `confirmChangeLenderAddress(_lender: uint256)`
- `createPool(_params: PoolParams, _andSupply: uint256, _allowance: uint256) → bytes32`
- `supplyPool(_poolId: bytes32, _amount: uint256)`
- `setAllowance(_poolId: bytes32, _amount: uint256)`
- `setAllowedToBorrow(_poolId: bytes32, _nodes: DynArray[address, MAX_ADDRESS_BATCH], _allowed: bool)`
- `withdrawFromPool(_poolId: bytes32, _amount: uint256)`
- `withdrawInterest(_poolId: bytes32, _amount: uint256, _andSupply: uint256)`
- `withdrawEtherFromPool(_poolId: bytes32, _amount: uint256)`
- `forceRepayRPL(_poolId: bytes32, _node: address, _withdrawAmount: uint256)`
- `forceRepayETH(_poolId: bytes32, _node: address)`
- `forceClaimMerkleRewards(_poolId: bytes32, _node: address, _repayRPL: uint256, _repayETH: uint256, _rewardIndex: DynArray[uint256, MAX_CLAIM_INTERVALS], _amountRPL: DynArray[uint256, MAX_CLAIM_INTERVALS], _amountETH: DynArray[uint256, MAX_CLAIM_INTERVALS], _merkleProof: DynArray[DynArray[bytes32, MAX_PROOF_LENGTH], MAX_CLAIM_INTERVALS])`
- `forceDistributeRefund(_poolId: bytes32, _node: address, _distribute: bool, _distributeMinipools: DynArray[address, MAX_NODE_MINIPOOLS], _rewardsOnly: bool, _refundMinipools: DynArray[address, MAX_NODE_MINIPOOLS])`

### Borrower functions
- `changeBorrowerAddress(_node: address, _newAddress: address, _confirm: bool)`
- `confirmChangeBorrowerAddress(_node: address)`
- `joinAsBorrower(_node: address)`
- `leaveAsBorrower(_node: address)`
- `stakeRPLFor(_node: address, _amount: uint256)`
- `withdrawRPL(_node: address, _amount: uint256)`
- `borrow(_poolId: bytes32, _node: address, _amount: uint256)`
- `repay(_poolId: bytes32, _node: address, _amount: uint256, _amountSupplied: uint256)`
- `transferDebt(_node: address, _fromPool: bytes32, _toPool: bytes32, _fromAvailable: uint256, _fromInterest: uint256, _fromAllowance: uint256)`
- `claimMerkleRewards(_node: address, _rewardIndex: DynArray[uint256, MAX_CLAIM_INTERVALS], _amountRPL: DynArray[uint256, MAX_CLAIM_INTERVALS], _amountETH: DynArray[uint256, MAX_CLAIM_INTERVALS], _merkleProof: DynArray[DynArray[bytes32, MAX_PROOF_LENGTH], MAX_CLAIM_INTERVALS], _stakeAmount: uint256)`
- `distribute(_node: address)`
- `distributeMinipools(_node: address, _minipools: DynArray[address, MAX_NODE_MINIPOOLS], _rewardsOnly: bool)`
- `refundMinipools(_node: address, _minipools: DynArray[address, MAX_NODE_MINIPOOLS])`
- `withdraw(_node: address, _amountRPL: uint256, _amountETH: uint256)`

### Events

- `UpdateAdmin`
    - `old: address`
    - `new: address`
- `RegisterLender`
    - `id: uint256`
    - `address: address`
- `UpdateLender`
    - `id: uint256`
    - `old: address`
    - `new: address`
- `CreatePool`
    - `id: bytes32`
    - `params: PoolParams`
- `SupplyPool`
    - `id: bytes32`
    - `amount: uint256`
    - `total: uint256`
- `SetAllowance`
    - `id: bytes32`
    - `old: uint256`
    - `new: uint256`
- `WithdrawFromPool`
    - `id: bytes32`
    - `amount: uint256`
    - `total: uint256`
- `WithdrawInterest`
    - `id: bytes32`
    - `amount: uint256`
    - `supplied: uint256`
    - `interestPaid: uint256`
    - `available: uint256`
- `WithdrawEtherFromPool`
    - `id: bytes32`
    - `amount: uint256`
    - `total: uint256`
- `ForceRepayRPL`
    - `id: bytes32`
    - `node: address`
    - `withdrawn: uint256`
    - `available: uint256`
    - `borrowed: uint256`
    - `interestDue: uint256`
- `ForceRepayETH`
    - `id: bytes32`
    - `node: address`
    - `amount: uint256`
    - `available: uint256`
    - `borrowed: uint256`
    - `interestDue: uint256`
- `ForceClaimRewards`
    - `id: bytes32`
    - `node: address`
    - `claimedRPL: uint256`
    - `claimedETH: uint256`
    - `repaidRPL: uint256`
    - `repaidETH: uint256`
    - `RPL: uint256`
    - `ETH: uint256`
    - `borrowed: uint256`
    - `interestDue: uint256`
- `ForceDistributeRefund`
    - `id: bytes32`
    - `node: address`
    - `claimed: uint256`
    - `repaid: uint256`
    - `available: uint256`
    - `borrowed: uint256`
    - `interestDue: uint256`
- `UpdateBorrower`
    - `node: address`
    - `old: address`
    - `new: address`
- `JoinProtocol`
    - `node: address`
- `LeaveProtocol`
    - `node: address`
- `WithdrawRPL`
    - `node: address`
    - `amount: uint256`
    - `total: uint256`
- `Borrow`
    - `pool: bytes32`
    - `node: address`
    - `amount: uint256`
    - `borrowed: uint256`
    - `interestDue: uint256`
- `Repay`
    - `pool: bytes32`
    - `node: address`
    - `amount: uint256`
    - `borrowed: uint256`
    - `interestDue: uint256`
- `TransferDebt`
    - `node: address`
    - `fromPool: bytes32`
    - `toPool: bytes32`
    - `amount: uint256`
    - `interestDue: uint256`
    - `allowance: uint256`
- `Distribute`
    - `node: address`
    - `amount: uint256`
- `DistributeMinipools`
    - `node: address`
    - `amount: uint256`
    - `total: uint256`
- `RefundMinipools`
    - `node: address`
    - `amount: uint256`
    - `total: uint256`
- `ClaimRewards`
    - `node: address`
    - `claimedRPL: uint256`
    - `claimedETH: uint256`
    - `stakedRPL: uint256`
    - `totalRPL: uint256`
    - `totalETH: uint256`
    - `index: uint256`
- `Withdraw`
    - `node: address`
    - `amountRPL: uint256`
    - `amountETH: uint256`
    - `totalRPL: uint256`
    - `totalETH: uint256`

## Security Considerations

TODO: discuss incentives for various scenarios
TODO: discuss possibilities for funds getting locked
TODO: discuss affects of RPL price volatility for defaults
TODO: discuss upgrades (of Rocket Pool, beacon chain, Rocket Lend, etc.)
TODO: smart contract risk, risks and benefits of the technical design, audits
