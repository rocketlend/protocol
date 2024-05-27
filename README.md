# RPL

RPL Pooled Lending ("RPL", or "RPL protocol" when ambiguous) is a protocol for
lending/borrowing RPL to stake on Rocket Pool nodes.

No collateral asset is required to borrow RPL from lenders because the borrowed
RPL is immediately staked on a node, and the withdrawal address for the node is
verified to be the RPL protocol smart contract that will enforce the terms of
the loan. Another way to think of it is that the collateral for the loan is the
node's staked assets (ETH and RPL).

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

Although each pool has a single lender, the relationship between borrowers and
pools is many to many. A given pool may lend RPL to many borrowers, and a given
borrower may borrow RPL from many pools.

In return for providing RPL to be staked, lenders expect to receive interest.
The interest rate is specified by the lender up front. It is charged on RPL
that is actually borrowed, for the time during the loan term that it is
borrowed.

The lender also expects to eventually be repaid the RPL provided to the
protocol, minus a protocol fee taken by the protocol itself, assessed as a flat
percentage of any RPL that was actually borrowed and repaid.

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

### Borrower Actions

Borrowers can use the RPL protocol contract to:

- Register as a borrower in the protocol by confirming their node's primary and
  RPL withdrawal addresses as the RPL protocol contract
- Stake RPL from a pool onto their node
- Repay a pool by withdrawing RPL from their node
- Repay a pool by supplying fresh RPL - this may also be done by a third party
  on the borrower's behalf
- Withdraw excess RPL (after repaying any debt) from their node to their
  withdrawal address
- Withdraw ETH rewards from their node to their withdrawal address
- Withdraw unstaked ETH from their node to their withdrawal address
- Change their (RPL protocol) withdrawal address
- Exit the RPL protocol by changing their node's primary and RPL withdrawal
  addresses

TODO: transferring debt to another loan

#### Borrow Limit

The total amount borrowed at any time by a borrower is limited by the ETH and
RPL the protocol can determine is available for repayment. This reduces the
incentive for a node operator to lock up borrowed RPL with no intention of ever
using it.

The borrow limit is the value of the following: ETH bonded to currently active
minipools, ETH supplied (via stake on behalf) for creating new minipools, and
any RPL and ETH held in the RPL protocol (e.g. after being claimed or withdrawn
from Rocket Pool). It is denominated in RPL using the current RPL price from
Rocket Pool.

Rewards are not included, so if a borrower reaches their borrow limit, they
should claim rewards to be able to borrow more.

### Lender Actions

Lenders can use the RPL protocol contract to:

- Register as a lender in the protocol by claiming a new identifier
- Transfer control (ownership of funds) of their lender identifier to a new
  address
- Create a new lending pool with their chosen parameters
- Supply RPL to one of their lending pools - this may also be done by a third
  party on the lender's behalf
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

TODO: document all contract functions in detail

## Security Considerations

TODO: discuss incentives for various scenarios
TODO: discuss possibilities for funds getting locked
TODO: discuss affects of RPL price volatility for defaults
TODO: discuss upgrades (of Rocket Pool, beacon chain, RPL protocol, etc.)
TODO: smart contract risk, risks and benefits of the technical design, audits
