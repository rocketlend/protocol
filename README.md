# Rocket Lend

Rocket Lend is a protocol for lending/borrowing RPL to stake on Rocket Pool
nodes.

No additional collateral asset is required to borrow RPL from lenders because
the borrowed RPL is immediately staked on a node, and the withdrawal address
for the node is verified to be the Rocket Lend smart contract that will enforce
the terms of the loan (as much as possible as withdrawal address). Another way
to think of it is that the collateral for the loan is the node's staked ETH.

## Technical Design

Rocket Lend consists of a single immutable smart contract ("the Rocket Lend
contract"), used for all interaction with the protocol and designed to be the
primary and RPL withdrawal address for Rocket Pool nodes that borrow RPL from
the protocol.

The protocol participants come in two types: "lenders", who supply RPL to the
protocol, and "borrowers" who borrow RPL from the protocol to stake on Rocket
Pool nodes.

A lender is assigned a unique identifier when they register with Rocket Lend.
They provide an address to which funds from Rocket Lend will be sent, which can
be changed.

A borrower is identified by the address of the Rocket Pool node they are
borrowing for. They also provide an address to Rocket Lend (initially the
node's withdrawal address before Rocket Lend), which can be changed, to which
their funds are ultimately sent.

### Lending Pools

The Rocket Lend contract manages pools of RPL that are made available by
lenders to be used by borrowers. There may be many pools active at once. Each
lender may have any number of pools.

Although each pool has a single lender, the relationship between borrowers and
pools is many to many. A given pool may lend RPL to many borrowers, and a given
borrower may borrow RPL from many pools.

In return for providing RPL to be staked, lenders expect to receive interest.
The interest rate is specified by the lender when the pool is created. It is
charged on RPL that is actually borrowed, for the time during the loan term
that it is borrowed. After the loan term, if there is outstanding debt it is
charged interest at double the rate. The lender also expects to eventually be
repaid the RPL they supplied to a lending pool.

Each pool is identified by the following parameters:
- Lender: the identifier for the lender, who receives repaid RPL and interest.
- Interest rate: the percentage rate (RPL per RPL borrowed, as a percentage,
  per year), charged as interest to the borrower. Interest is charged on the
  borrowed amount, i.e., without compounding, at one-second granularity. Only a
  whole number percentage can be specified.
- End time: the time by which the lender wishes the pool's RPL to be repaid.
  After this time, the interest rate doubles, and outstanding debt plus
  interest can be seized by the lender from any of the borrower's RPL or ETH as
  it is withdrawn.

RPL may be supplied to a pool (without changing its parameters) at any time.
RPL that is not currently borrowed may be withdrawn from the pool at any time.

Lending pools can be restricted to a limited set of borrowers. The set of
borrowers that are allowed to borrow from a pool can be changed at any time by
the lender (without changing the parameters that identify the pool).

### Borrower Actions

Borrowers can use the Rocket Lend contract to:

- Register as a borrower in the protocol by confirming their node's primary and
  RPL withdrawal addresses as the Rocket Lend contract
- Change their (Rocket Lend) borrower address
- Stake RPL from a pool onto their node
- Repay a pool by withdrawing RPL from their node
- Repay a pool by supplying fresh RPL - this may also be done by a third party
  on the borrower's behalf
- Transfer their debt from one pool to another (repaying the source with a
  borrow from the target pool). If the target pool belongs to the same lender,
  this can be done up to the lender's allowance for transfers without requiring
  available funds in the target pool
- Withdraw RPL stake or claim RPL or ETH rewards (after repaying any debt) from
  their node to their balance in Rocket Lend. This includes handling Merkle
  rewards
- Withdraw ETH rewards and/or unstaked ETH from their node to their balance in
  Rocket Lend. This includes handling minipool distributions and refunds, and
  fee distributor distributions
- Withdraw RPL and/or ETH from Rocket Lend to their borrower address, as long
  as they remain within the borrow limit
- Deposit ETH from their balance in Rocket Lend back onto their Rocket Pool
  node
- Exit Rocket Lend by changing their node's primary and RPL withdrawal
  addresses

#### Borrow Limit

The total amount borrowed by a borrower (plus interest) is limited by the ETH
staked (or deposited for staking) on their node (or withdrawn to Rocket Lend).
This reduces the incentive for a node operator to lock up borrowed RPL with no
intention of ever using it.

The borrow limit is 50% of the value of the borrower's "available ETH", defined
as: ETH bonded to currently active minipools, ETH supplied (via stake on
behalf) for creating new minipools, and ETH withdrawn from the node into the
borrower's Rocket Lend balance. (Unclaimed rewards are not included.) It is
denominated in RPL using the RPL price from Rocket Pool at the time the limit
is checked, that is, when RPL is borrowed.

The borrow limit is also checked when ETH is withdrawn from Rocket Lend, but
for withdrawals the limit is doubled. In other words, when withdrawing ETH from
Rocket Lend, we ensure that the borrower's borrowed RPL plus unpaid interest
remains below 100% of the borrower's available ETH.

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
- Set the allowance for transfers of debt into one of their lending pools from
  their other lending pools
- Withdraw RPL that is not currently borrowed from one of their lending pools
- Withdraw any interest paid to one of their lending pools, and optionally
  supply it back to the pool
- Withdraw any remaining debt (borrowed RPL plus interest) from a node after
  the end time of the lending pool
- Force a claim/withdrawal of ETH or RPL from the node of a borrower that has
  defaulted on a loan from one of the lender's pools, up to the outstanding
  debt amount

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
|`BORROW_LIMIT_PERCENT` |      50 |                      |

### Structs

- `PoolParams` (per pool id)
  - `lender: uint256`: identifier (non-negative integer) of the pool owner
  - `interestRate: uint8`: interest rate (APR) as a whole-number percentage
  - `endTime: uint256`: seconds after the Unix epoch when the loan ends

- `PoolState` (per pool id)
  - `available: uint256`: amount of RPL available to be borrowed or returned to the lender
  - `borrowed: uint256`: amount of RPL currently borrowed
  - `allowance: uint256`: limit on how much RPL can be made available by transferring either borrowed RPL from another of the lender's pools, or interest from another of the lender's loans
  - `interestPaid: uint256`: interest the pool has accrued (available to be claimed by the lender)
  - `reclaimed: uint256`: amount of ETH accrued in service of defaults (available to be claimed by the lender)

- `LoanState` (per pool id and node (borrower))
  - `borrowed: uint256`: amount of RPL currently borrowed in this loan
  - `startTime: uint256`: start time for ongoing interest accumulation on the `borrowed` amount
  - `interestDue: uint256`: interest due (accrued before `startTime`) but not yet paid by the borrower

- `BorrowerState` (per node)
  - `borrowed: uint256`: total RPL borrowed
  - `interestDue: uint256`: interest due, not including ongoing interest on `borrowed`, but not yet paid
  - `RPL: uint256`: amount of RPL available for (with priority) debt repayments or to be withdrawn
  - `ETH: uint256`: amount of ETH available for (with priority) debt repayments on liquidation or to be withdrawn
  - `index: uint256`: first not-yet-accounted-for Rocket Pool rewards interval index
  - `address: address`: current (Rocket Lend) withdrawal address for the borrower
  - `pending: address`: pending address used when changing the borrower address

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
- `createPool(_params: PoolParams, _andSupply: uint256, _allowance: uint256, _borrowers: DynArray[address, MAX_ADDRESS_BATCH]) → bytes32`
- `supplyPool(_poolId: bytes32, _amount: uint256)`
- `setAllowance(_poolId: bytes32, _amount: uint256)`
- `changeAllowedToBorrow(_poolId: bytes32, _allowed: bool, _nodes: DynArray[address, MAX_ADDRESS_BATCH])`
- `withdrawFromPool(_poolId: bytes32, _amount: uint256)`
- `chargeInterest(_poolId: bytes32, _node: address)`: can be called by anyone
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
- `setStakeRPLForAllowed(_node: address, _caller: address, _allowed: bool)`
- `withdrawRPL(_node: address, _amount: uint256)`
- `borrow(_poolId: bytes32, _node: address, _amount: uint256)`
- `repay(_poolId: bytes32, _node: address, _withdrawAmount: uint256, _repayAmount: uint256)`
- `transferDebt(_node: address, _fromPool: bytes32, _toPool: bytes32, _fromAvailable: uint256, _fromInterest: uint256, _fromAllowance: uint256)`
- `claimMerkleRewards(_node: address, _rewardIndex: DynArray[uint256, MAX_CLAIM_INTERVALS], _amountRPL: DynArray[uint256, MAX_CLAIM_INTERVALS], _amountETH: DynArray[uint256, MAX_CLAIM_INTERVALS], _merkleProof: DynArray[DynArray[bytes32, MAX_PROOF_LENGTH], MAX_CLAIM_INTERVALS], _stakeAmount: uint256)`
- `distribute(_node: address)`
- `distributeMinipools(_node: address, _minipools: DynArray[address, MAX_NODE_MINIPOOLS], _rewardsOnly: bool)`
- `refundMinipools(_node: address, _minipools: DynArray[address, MAX_NODE_MINIPOOLS])`
- `withdraw(_node: address, _amountRPL: uint256, _amountETH: uint256)`
- `depositETH(_node: address, _amount: uint256)`

### Events

- `RegisterLender`
    - `id: indexed(uint256)`
    - `address: indexed(address)`
- `UpdateLender`
    - `id: indexed(uint256)`
    - `old: indexed(address)`
    - `new: indexed(address)`
- `CreatePool`
    - `id: indexed(bytes32)`
    - `params: PoolParams`
- `SupplyPool`
    - `id: indexed(bytes32)`
    - `amount: indexed(uint256)`
    - `total: indexed(uint256)`
- `SetAllowance`
    - `id: indexed(bytes32)`
    - `old: indexed(uint256)`
    - `new: indexed(uint256)`
- `ChangeAllowedToBorrow`
    - `id: indexed(bytes32)`
    - `allowed: indexed(bool)`
    - `nodes: DynArray[address, MAX_ADDRESS_BATCH]`
- `WithdrawFromPool`
    - `id: indexed(bytes32)`
    - `amount: indexed(uint256)`
    - `total: indexed(uint256)`
- `ChargeInterest`
    - `id: indexed(bytes32)`
    - `node: indexed(address)`
    - `charged: uint256`
    - `total: uint256`
    - `until: uint256`
- `WithdrawInterest`
    - `id: indexed(bytes32)`
    - `amount: indexed(uint256)`
    - `supplied: indexed(uint256)`
    - `interestPaid: uint256`
    - `available: uint256`
- `WithdrawEtherFromPool`
    - `id: indexed(bytes32)`
    - `amount: indexed(uint256)`
    - `total: indexed(uint256)`
- `ForceRepayRPL`
    - `id: indexed(bytes32)`
    - `node: indexed(address)`
    - `withdrawn: indexed(uint256)`
    - `available: uint256`
    - `borrowed: uint256`
    - `interestDue: uint256`
- `ForceRepayETH`
    - `id: indexed(bytes32)`
    - `node: indexed(address)`
    - `amount: indexed(uint256)`
    - `available: uint256`
    - `borrowed: uint256`
    - `interestDue: uint256`
- `ForceClaimRewards`
    - `id: indexed(bytes32)`
    - `node: indexed(address)`
    - `claimedRPL: uint256`
    - `claimedETH: uint256`
    - `repaidRPL: uint256`
    - `repaidETH: uint256`
    - `RPL: uint256`
    - `ETH: uint256`
    - `borrowed: uint256`
    - `interestDue: uint256`
- `ForceDistributeRefund`
    - `id: indexed(bytes32)`
    - `node: indexed(address)`
    - `claimed: uint256`
    - `repaid: uint256`
    - `available: uint256`
    - `borrowed: uint256`
    - `interestDue: uint256`
- `UpdateBorrower`
    - `node: indexed(address)`
    - `old: indexed(address)`
    - `new: indexed(address)`
- `JoinProtocol`
    - `node: indexed(address)`
- `LeaveProtocol`
    - `node: indexed(address)`
- `WithdrawRPL`
    - `node: indexed(address)`
    - `amount: indexed(uint256)`
    - `total: indexed(uint256)`
- `Borrow`
    - `pool: indexed(bytes32)`
    - `node: indexed(address)`
    - `amount: indexed(uint256)`
    - `borrowed: uint256`
    - `interestDue: uint256`
- `Repay`
    - `pool: indexed(bytes32)`
    - `node: indexed(address)`
    - `amount: indexed(uint256)`
    - `borrowed: uint256`
    - `interestDue: uint256`
- `TransferDebt`
    - `node: indexed(address)`
    - `fromPool: indexed(bytes32)`
    - `toPool: indexed(bytes32)`
    - `amount: uint256`
    - `interestDue: uint256`
    - `allowance: uint256`
- `Distribute`
    - `node: indexed(address)`
    - `amount: indexed(uint256)`
- `DistributeMinipools`
    - `node: indexed(address)`
    - `amount: indexed(uint256)`
    - `total: indexed(uint256)`
- `RefundMinipools`
    - `node: indexed(address)`
    - `amount: indexed(uint256)`
    - `total: indexed(uint256)`
- `ClaimRewards`
    - `node: indexed(address)`
    - `claimedRPL: indexed(uint256)`
    - `claimedETH: indexed(uint256)`
    - `stakedRPL: uint256`
    - `totalRPL: uint256`
    - `totalETH: uint256`
    - `index: uint256`
- `Withdraw`
    - `node: indexed(address)`
    - `amountRPL: indexed(uint256)`
    - `amountETH: indexed(uint256)`
    - `totalRPL: uint256`
    - `totalETH: uint256`
- `DepositETH`
    - `node: indexed(address)`
    - `amount: indexed(uint256)`
    - `total: indexed(uint256)`

## Additional Information

TODO: discuss RPL slashing
TODO: discuss poorly performing or abandoned nodes
TODO: discuss possible griefing vectors and mitigations
TODO: discuss incentives for various scenarios
TODO: discuss possibilities for funds getting locked
TODO: discuss affects of RPL price volatility for defaults
TODO: discuss upgrades (of Rocket Pool, beacon chain, Rocket Lend, etc.)
TODO: smart contract risk, risks and benefits of the technical design, audits
