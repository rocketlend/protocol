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

A lender is identified by their Ethereum address. They can create lending
pools, which are transferable to other addresses.

A borrower is identified by the address of the Rocket Pool node they are
borrowing for. They also provide an address (their "borrower address") to
Rocket Lend (initially the node's withdrawal address before Rocket Lend), which
can be changed, to which their funds are ultimately sent.

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

Each pool is identified by a unique number.

Pools are created with the following parameters which cannot be changed:
- Interest rate: the percentage rate (RPL per RPL borrowed, as a percentage,
  per year), charged as interest to the borrower. Interest is charged on the
  borrowed amount, i.e., without compounding, at one-second granularity. Only a
  whole number percentage can be specified.
- End time: the time by which the lender wishes the pool's RPL to be repaid.
  After this time, the interest rate doubles, and outstanding debt plus
  interest can be seized by the lender from any of the borrower's RPL or ETH as
  it is withdrawn.

RPL may be supplied to a pool at any time. RPL that is not currently borrowed
may be withdrawn from the pool at any time. Debt in a pool can be transferred
to another pool (if the same lender owns both pools and specifies the extent to
which they permit such transfers).

Lending pools can be restricted to a limited set of borrowers. The set of
borrowers that are allowed to borrow from a pool can be changed at any time by
the lender.

### Borrower Actions

Borrowers can use the Rocket Lend contract to:

- Register as a borrower in the protocol by confirming their node's primary and
  RPL withdrawal addresses as the Rocket Lend contract
- Change their (Rocket Lend) borrower address
- Stake RPL from a pool (i.e. borrow it) onto their node
- Repay a pool by withdrawing RPL from their node
- Repay a pool by supplying fresh RPL - this may also be done by a third party
  on the borrower's behalf
- Transfer their debt from one pool to another (repaying the source with a
  borrow from the target pool). If the target pool belongs to the same lender,
  this can be done up to the lender's allowance for transfers without requiring
  available funds in the target pool
- Withdraw ETH rewards and/or unstaked ETH from their node to their balance in
  Rocket Lend. This includes handling minipool distributions and refunds, and
  fee distributor distributions
- Withdraw RPL and ETH Merkle rewards from Rocket Pool into the borrower's
  Rocket Lend balance
- Withdraw RPL and/or ETH from Rocket Lend to their borrower address. The
  available RPL (in Rocket Lend and staked on their node) after withdrawing
  must cover the borrower's total debt (including interest), and the available
  ETH must be sufficient for the borrow limit check (described below).
  Withdrawal is disallowed if the borrower has debt in an expired pool.
- Stake RPL from their balance in Rocket Lend back onto their node
- Deposit ETH from their balance in Rocket Lend back onto their node
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

- Create a new lending pool with their chosen parameters
- Transfer a lending pool to another address
- Restrict or expand the set of borrowers that are allowed to borrow RPL from
  one of their lending pools
- Set the allowance for transfers of debt into one of their lending pools from
  their other lending pools
- Supply RPL to one of their lending pools - this may also be done by a third
  party on the lender's behalf
- Withdraw RPL that is not currently borrowed (including repayments and
  interest) from one of their lending pools
- Withdraw ETH that was reclaimed from a default from one of their lending
  pools
- Unstake any remaining defaulted debt (borrowed RPL plus interest) from
  a node after the end time of the lending pool, as long as the RPL is
  withdrawable from Rocket Pool
- Force a claim/withdrawal of ETH or RPL rewards from the node of a borrower
  that has defaulted on a loan from one of the lender's pools, up to the
  outstanding debt amount

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
  - `interestRate: uint8`: interest rate (APR) as a whole-number percentage
  - `endTime: uint256`: seconds after the Unix epoch when the loan ends

- `PoolState` (per pool id)
  - `lender: address`: the pool owner
  - `available: uint256`: amount of RPL available to be borrowed or returned to the lender
  - `borrowed: uint256`: amount of RPL currently borrowed
  - `allowance: uint256`: limit on how much RPL can be made available by transferring either borrowed RPL from another of the lender's pools, or interest from another of the lender's loans
  - `reclaimed: uint256`: amount of ETH accrued in service of defaults (available to be claimed by the lender)

- `LoanState` (per pool id and node (borrower))
  - `borrowed: uint256`: amount of RPL currently borrowed in this loan
  - `interestDue: uint256`: interest due (accrued before `accountedUntil`) but not yet paid by the borrower
  - `accountedUntil: uint256`: start time for ongoing interest accumulation on the `borrowed` amount

- `BorrowerState` (per node)
  - `borrowed: uint256`: total RPL borrowed
  - `interestDue: uint256`: interest due, not including ongoing interest on `borrowed`, but not yet paid
  - `RPL: uint256`: amount of RPL available for (with priority) debt repayments or to be withdrawn
  - `ETH: uint256`: amount of ETH available for (with priority) debt repayments on liquidation or to be withdrawn
  - `index: uint256`: first not-yet-accounted-for Rocket Pool rewards interval index
  - `address: address`: current (Rocket Lend) borrower address
  - `pending: address`: pending address used when changing the borrower address

- `MinipoolArgument`
  - `index: uint256`: index of minipool on node
  - `action: uint256`: bitfield (flag) with 3 bits:
    - bit 0: distribute this minipool
    - bit 1: set `rewardsOnly` to false when distributing
    - bit 2: refund this minipool

- `PoolItem`
  - `next: uint256`
  - `poolId: uint256`

### Views

- `nextPoolId() → uint256`
- `params(poolId: uint256) → PoolParams`
- `pools(poolId: uint256) → PoolState`
- `loans(poolId: uint256, node: address) → LoanState`
- `allowedToBorrow(poolId: uint256, node: address) → bool`: if the null address is allowed, anyone is
- `borrowers(node: address) → BorrowerState`
- `intervals(node: address, index: uint256) → bool`: whether a rewards interval index is known to be claimed
- `debtPools(node: address, index: uint256) → PoolItem`
- `rocketStorage() → address`: the address of the Rocket Storage contract
- `RPL() → address`: the address of the RPL token contract

### Lender functions

- `createPool(_params: PoolParams, _supply: uint256, _allowance: uint256, _borrowers: DynArray[address, MAX_ADDRESS_BATCH]) → uint256`
- `transferPool(_poolId: uint256, _newLender: address, _confirm: bool)`
- `confirmTransferPool(_poolId: uint256)`
- `changePoolRPL(_poolId: uint256, _targetSupply: uint256)`: can be called by anyone if only supplying
- `withdrawEtherFromPool(_poolId: uint256, _amount: uint256)`
- `changeAllowedToBorrow(_poolId: uint256, _borrowers: DynArray[uint256, MAX_ADDRESS_BATCH])`
- `setAllowance(_poolId: uint256, _allowance: uint256)`
- `updateInterestDue(_poolId: uint256, _node: address)`: can be called by anyone
- `forceRepayRPL(_poolId: uint256, _node: address, _prevIndex: uint256, _unstakeAmount: uint256)`: can be called by anyone
- `forceRepayETH(_poolId: uint256, _node: address, _prevIndex: uint256)`
- `forceClaimMerkleRewards(_poolId: uint256, _node: address, _prevIndex: uint256, _repayRPL: uint256, _repayETH: uint256, _rewardIndex: DynArray[uint256, MAX_CLAIM_INTERVALS], _amountRPL: DynArray[uint256, MAX_CLAIM_INTERVALS], _amountETH: DynArray[uint256, MAX_CLAIM_INTERVALS], _merkleProof: DynArray[DynArray[bytes32, MAX_PROOF_LENGTH], MAX_CLAIM_INTERVALS])`
- `forceDistributeRefund(_poolId: uint256, _node: address, _prevIndex: uint256, _distribute: bool, _minipools: DynArray[MinipoolArgument, MAX_NODE_MINIPOOLS])`

### Borrower functions

- `changeBorrowerAddress(_node: address, _newAddress: address, _confirm: bool)`
- `confirmChangeBorrowerAddress(_node: address)`
- `joinAsBorrower(_node: address)`
- `leaveAsBorrower(_node: address)`
- `setStakeRPLForAllowed(_node: address, _caller: address, _allowed: bool)`
- `unstakeRPL(_node: address, _amount: uint256)`
- `borrow(_poolId: uint256, _node: address, _amount: uint256)`
- `repay(_poolId: uint256, _node: address, _prevIndex: uint256, _unstakeAmount: uint256, _repayAmount: uint256)`
- `transferDebt(_node: address, _fromPool: uint256, _fromPrevIndex: uint256, _toPool: uint256, _toPrevIndex: uint256, _fromAvailable: uint256, _fromInterest: uint256, _fromAllowance: uint256)`
- `claimMerkleRewards(_node: address, _rewardIndex: DynArray[uint256, MAX_CLAIM_INTERVALS], _amountRPL: DynArray[uint256, MAX_CLAIM_INTERVALS], _amountETH: DynArray[uint256, MAX_CLAIM_INTERVALS], _merkleProof: DynArray[DynArray[bytes32, MAX_PROOF_LENGTH], MAX_CLAIM_INTERVALS], _stakeAmount: uint256)`
- `distributeRefund(_node: address, _distribute: bool, _minipools: DynArray[MinipoolArgument, MAX_NODE_MINIPOOLS])`
- `withdraw(_node: address, _amountRPL: uint256, _amountETH: uint256)`
- `stakeRPLFor(_node: address, _amount: uint256)`
- `depositETHFor(_node: address, _amount: uint256)`

### Events

- `CreatePool`
    - `id: indexed(uint256)`
- `PendingTransferPool`
    - `old: indexed(address)`
- `ConfirmTransferPool`
    - `old: indexed(address)`
    - `oldPending: indexed(address)`
- `SupplyPool`
    - `id: indexed(uint256)`
    - `total: indexed(uint256)`
- `SetAllowance`
    - `id: indexed(uint256)`
    - `old: indexed(uint256)`
- `ChangeAllowedToBorrow`
    - `id: indexed(uint256)`
    - `node: indexed(address)`
    - `allowed: indexed(bool)`
- `WithdrawETHFromPool`
- `WithdrawRPLFromPool`
- `ForceRepayRPL`
    - `available: indexed(uint256)`
    - `borrowed: indexed(uint256)`
    - `interestDue: indexed(uint256)`
- `ForceRepayETH`
    - `available: indexed(uint256)`
    - `borrowed: indexed(uint256)`
    - `interestDue: indexed(uint256)`
    - `amount: uint256`
- `ForceClaimRewards`
    - `RPL: indexed(uint256)`
    - `ETH: indexed(uint256)`
    - `borrowed: uint256`
    - `interestDue: uint256`
- `ForceDistributeRefund`
    - `claimed: indexed(uint256)`
    - `repaid: indexed(uint256)`
    - `available: uint256`
    - `borrowed: uint256`
    - `interestDue: uint256`
- `ChargeInterest`
    - `charged: uint256`
    - `total: uint256`
- `PendingChangeBorrowerAddress`
    - `old: indexed(address)`
- `ConfirmChangeBorrowerAddress`
    - `old: indexed(address)`
    - `oldPending: indexed(address)`
- `JoinProtocol`
    - `borrower: indexed(address)`
- `LeaveProtocol`
    - `oldPending: indexed(address)`
- `UnstakeRPL`
    - `total: indexed(uint256)`
- `Borrow`
    - `borrowed: indexed(uint256)`
    - `interestDue: indexed(uint256)`
- `Repay`
    - `amount: indexed(uint256)`
    - `borrowed: indexed(uint256)`
    - `interestDue: indexed(uint256)`
- `TransferDebt`
- `DistributeRefund`
    - `amount: indexed(uint256)`
    - `total: indexed(uint256)`
- `ClaimRewards`
    - `totalRPL: indexed(uint256)`
    - `totalETH: indexed(uint256)`
    - `index: indexed(uint256)`
- `Withdraw`
    - `totalRPL: indexed(uint256)`
    - `totalETH: indexed(uint256)`
- `StakeRPLFor`
    - `total: indexed(uint256)`
- `DepositETHFor`
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
