#pragma version ^0.3.0

interface RPLInterface:
  def transferFrom(_from: address, _to: address, _value: uint256) -> bool: nonpayable

interface RocketStorageInterface:
  def getAddress(_key: bytes32) -> address: view
  def getNodeWithdrawalAddress(_nodeAddress: address) -> address: view
  def confirmWithdrawalAddress(_nodeAddress: address): nonpayable
  def setWithdrawalAddress(_nodeAddress: address, _newWithdrawalAddress: address, _confirm: bool): nonpayable

interface RocketNodeStakingInterface:
  def getNodeRPLStake(_nodeAddress: address) -> uint256: view
  def stakeRPLFor(_nodeAddress: address, _amount: uint256): nonpayable
rocketNodeStakingKey: constant(bytes32) = keccak256("contract.addressrocketNodeStaking")

RPL: public(immutable(RPLInterface))
rocketStorage: public(immutable(RocketStorageInterface))

@external
def __init__():
  RPL = RPLInterface(0xD33526068D116cE69F19A9ee46F0bd304F21A51f)
  rocketStorage = RocketStorageInterface(0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46)

struct PoolParams:
  feeNum: uint256
  feeDen: uint256
  endTime: uint256

params: public(HashMap[bytes32, PoolParams])

struct PoolState:
  lender: address
  supplied: uint256
  unclaimedETH: uint256
  unclaimedRPL: uint256

pools: public(HashMap[bytes32, PoolState])

# (poolId, nodeAddress): RPL borrowed
borrowed: public(HashMap[bytes32, HashMap[address, uint256]])
totalBorrowed: public(HashMap[bytes32, uint256])

# nodeAddress: the node's next withdrawal address (using this contract as the first withdrawal address)
borrowerAddress: public(HashMap[address, address])

# nodeAddress: amounts unclaimed by borrowerAddress[nodeAddress]
unclaimedETH: public(HashMap[address, uint256])
unclaimedRPL: public(HashMap[address, uint256])

# poolId is unique for a lender, fee fraction, and end time
@internal
def _poolId(_lender: address, _params: PoolParams) -> bytes32:
  return keccak256(concat(
                     convert(_lender, bytes20),
                     convert(_params.feeNum, bytes32),
                     convert(_params.feeDen, bytes32),
                     convert(_params.endTime, bytes32)
                  ))

@external
def createPool(_params: PoolParams) -> bytes32:
  poolId: bytes32 = self._poolId(msg.sender, _params)
  self.pools[poolId].lender = msg.sender
  return poolId

# TODO: add fee amount (with maximum fraction) and fee recipient to supply

@internal
def _supply(_poolId: bytes32, _amount: uint256):
  assert RPL.transferFrom(msg.sender, self, _amount), "tf"
  self.pools[_poolId].supplied += _amount

# lender can supply RPL to one of their pools
@external
def supply(_poolId: bytes32, _amount: uint256):
  assert msg.sender == self.pools[_poolId].lender, "auth"
  self._supply(_poolId, _amount)

# supply RPL to a pool from another address
@external
def supplyOnBehalf(_poolId: bytes32, _amount: uint256):
  self._supply(_poolId, _amount)

# lender can withdraw supplied RPL after the end time (assuming the loan has been repaid)
@external
def withdraw(_poolId: bytes32):
  assert msg.sender == self.pools[_poolId].lender, "auth"
  assert self.params[_poolId].endTime <= block.timestamp, "term"
  assert self.totalBorrowed[_poolId] == 0, "not repaid"
  assert RPL.transferFrom(self, msg.sender, self.pools[_poolId].supplied), "tf"
  self.pools[_poolId].supplied = 0

# lender can withdraw supplied RPL that has not been borrowed, possibly before the end time
@external
def withdrawExcess(_poolId: bytes32, _amount: uint256):
  assert msg.sender == self.pools[_poolId].lender, "auth"
  assert _amount <= self.pools[_poolId].supplied - self.totalBorrowed[_poolId], "bal"
  assert RPL.transferFrom(self, msg.sender, _amount), "tf"
  self.pools[_poolId].supplied -= _amount

# TODO: claim merkle rewards
# TODO: distribute minipool and fee distributor rewards
# TODO: both of these should update any relevant unclaimedRPL and unclaimedETH
# pool states, as well as the unclaimedRPL and unclaimedETH borrower amounts
# ETH that goes to the lender is based on the pool fee
# RPL that goes to the lender is proportional to the amount the node borrowed vs its total RPL stake

# TODO: withdraw RPL from node
# TODO: withdraw ETH from node

@internal
def _getRocketNodeStaking() -> RocketNodeStakingInterface:
  rocketNodeStakingAddress: address = rocketStorage.getAddress(rocketNodeStakingKey)
  return RocketNodeStakingInterface(rocketNodeStakingAddress)

# lender can claim any unclaimed rewards that have arrived in this contract
# (which is the withdrawal address for borrowing nodes)
@external
def claimLenderRewards(_poolId: bytes32):
  assert msg.sender == self.pools[_poolId].lender, "auth"
  if 0 < self.pools[_poolId].unclaimedRPL:
    assert RPL.transferFrom(self, msg.sender, self.pools[_poolId].unclaimedRPL), "tf"
    self.pools[_poolId].unclaimedRPL = 0
  if 0 < self.pools[_poolId].unclaimedETH:
    send(msg.sender, self.pools[_poolId].unclaimedETH, gas=msg.gas)
    self.pools[_poolId].unclaimedETH = 0

@external
def borrow(_poolId: bytes32, _amount: uint256, _node: address):
  assert _amount + self.totalBorrowed[_poolId] <= self.pools[_poolId].supplied, "bal"
  assert rocketStorage.getNodeWithdrawalAddress(_node) == self, "wa"
  rocketNodeStaking: RocketNodeStakingInterface = self._getRocketNodeStaking()
  rocketNodeStaking.stakeRPLFor(_node, _amount)
  self.borrowed[_poolId][_node] += _amount
  self.totalBorrowed[_poolId] += _amount

@external
def repay(_poolId: bytes32, _amount: uint256, _amountSupplied: uint256):
  # TODO:
  pass
