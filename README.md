# RPL

RPL Pooled Lending ("RPL", or "RPL protocol" when ambiguous) is a protocol for
lending/borrowing RPL to stake on Rocket Pool nodes.

No collateral asset is required to borrow RPL from lenders because the borrowed
RPL is immediately staked on a node, and the withdrawal address for the node is
verified to be the RPL protocol smart contract that will enforce the terms of
the loan.

## Technical Design

The RPL protocol consists of a single smart contract ("the (RPL (protocol))
contract"), used for all interaction with the protocol and designed to be the
primary and RPL withdrawal address for Rocket Pool nodes that borrow RPL from
the protocol.

The protocol participants come in two types: "lenders", who supply RPL to the
protocol, and "borrowers" who borrow RPL from the protocol to stake on Rocket
Pool nodes.

A lender is assigned a unique identifier when they register with the RPL
protocol. They provide a withdrawal address (to which funds from the protocol
will be sent), which can be changed.

A borrower is identified by the Rocket Pool node they are borrowing for. They
also have a withdrawal address, which can be changed, to which their funds are
ultimately sent.

### Lending Pools

The contract manages pools of RPL that are made available by lenders to be used
by borrowers. There may be many pools active at once.

In return for providing RPL to be staked, lenders expect to receive "fees".
Fees derive from the RPL rewards and (a fraction of) the ETH rewards generated
by nodes. The rewards on which fees are assessed are proportional: they are
calculated in proportion to the fraction of a node's staked RPL that has been
provided by the lending pool at the time the node rewards are generated.

The lender also expects to eventually be repaid the RPL provided to the
protocol, minus a protocol fee taken by the protocol itself, assessed as a flat
percentage of any RPL that was actually borrowed and repaid.

Although each pool has a single lender, the relationship between borrowers and
pools is many to many. A given pool may lend RPL to many borrowers, and a given
borrower may borrow RPL from many pools.

Each pool is identified by the following parameters:
- Lender: the identifier for the lender, who will receive repaid RPL and fees
- End time: the time by which the lender wishes the pool's RPL to be repaid
- Fee fraction: the fraction of proportional ETH rewards the lender wishes to
  take as fees in addition to their proportional RPL rewards
- End condition: a boolean flag indicating whether borrowed RPL needs to be
  fully repaid by the end time, or whether it is sufficient for enough relevant
  validators to be exiting the beacon chain by the end time that it can be
  expected that the borrowed RPL will eventually become withdrawable (and hence
  repayable)

RPL may be supplied to a pool (without changing its parameters) at any time.
RPL that is not currently borrowed may be withdrawn from the pool at any time.

### Borrower Actions

Borrowers can use the RPL protocol contract to:

- Register as a borrower in the protocol by confirming their node's primary and
  RPL withdrawal addresses as the RPL protocol contract
- Stake RPL from a pool onto their node
- Repay a pool by withdrawing RPL from their node
- Repay a pool by supplying fresh RPL - this may also be done by a third party
  on the borrower's behalf
- Withdraw excess RPL (after repaying any loans) from their node to their
  withdrawal address
- Withdraw ETH rewards (after paying any fees) from their node to their
  withdrawal address
- Withdraw unstaked ETH from their node to their withdrawal address
- Change their (RPL protocol) withdrawal address
- Exit the RPL protocol by changing their node's primary and RPL withdrawal
  addresses

### Lender Actions

Lenders can use the RPL protocol contract to:

- Register as a lender in the protocol by claiming a new identifier
- Transfer control (fund ownership) of their lender identifier to a new address
- Create a new lending pool with their chosen parameters
- Supply RPL to one of their lending pools - this may also be done by a third
  party on the lender's behalf
- Withdraw RPL that is not currently borrowed from one of their lending pools
- Claim proportional RPL rewards from nodes whose RPL stake is (in part)
  borrowed from one of the lender's pools
- Claim fees from the proportional ETH rewards of nodes whose RPL stake is (in
  part) borrowed from one of the lender's pools
- Withdraw borrowed RPL from a node after the end time of the lending pool
- Claim penalties from any borrower that has defaulted on a loan from one of
  the lender's pools

### Penalties, Defaults, and Slashing

TODO: exponential penalty on ETH after end time
TODO: how defaulting is assessed?
TODO: how to handle RPL slashing
TODO: how to handle ETH slashing

## Contract API

TODO: document all contract functions in detail

## Security Considerations

TODO: discuss incentives for various scenarios
TODO: discuss possibilities for funds getting locked
TODO: discuss upgrades (of Rocket Pool, beacon chain, RPL protocol, etc.)
TODO: smart contract risk, risks and benefits of the technical design, audits
