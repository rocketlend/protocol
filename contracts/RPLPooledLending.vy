#pragma version ^0.3.0

interface RPLInterface:
  def transfer(_to: address, _value: uint256) -> bool: nonpayable
  def transferFrom(_from: address, _to: address, _value: uint256) -> bool: nonpayable

interface RocketStorageInterface:
  def getAddress(_key: bytes32) -> address: view
  def getBool(_key: bytes32) -> bool: view
  def getNodeWithdrawalAddress(_nodeAddress: address) -> address: view
  def confirmWithdrawalAddress(_nodeAddress: address): nonpayable
  def setWithdrawalAddress(_nodeAddress: address, _newWithdrawalAddress: address, _confirm: bool): nonpayable

interface RocketNodeManagerInterface:
  def getNodeRPLWithdrawalAddress(_nodeAddress: address) -> address: view
  def getNodeRPLWithdrawalAddressIsSet(_nodeAddress: address) -> bool: view
  def confirmRPLWithdrawalAddress(_nodeAddress: address): nonpayable
  def setRPLWithdrawalAddress(_nodeAddress: address, _newRPLWithdrawalAddress: address, _confirm: bool): nonpayable
  def unsetRPLWithdrawalAddress(_nodeAddress: address): nonpayable
rocketNodeManagerKey: constant(bytes32) = keccak256("contract.addressrocketNodeManager")

interface RocketNodeStakingInterface:
  def getNodeRPLStake(_nodeAddress: address) -> uint256: view
  def stakeRPLFor(_nodeAddress: address, _amount: uint256): nonpayable
  def withdrawRPL(_nodeAddress: address, _amount: uint256): nonpayable
rocketNodeStakingKey: constant(bytes32) = keccak256("contract.addressrocketNodeStaking")

interface RocketRewardsPoolInterface:
  def getRewardIndex() -> uint256: view
rocketRewardsPoolKey: constant(bytes32) = keccak256("contract.addressrocketRewardsPool")

MAX_INTERVALS: constant(uint256) = 128
MAX_PROOF_LENGTH: constant(uint256) = 32
MAX_FEE_PERCENT: constant(uint256) = 25

interface RocketMerkleDistributorInterface:
  def isClaimed(_rewardIndex: uint256, _nodeAddress: address) -> bool: view
  def claim(_nodeAddress: address,
            _rewardIndex: DynArray[uint256, MAX_INTERVALS],
            _amountRPL: DynArray[uint256, MAX_INTERVALS],
            _amountETH: DynArray[uint256, MAX_INTERVALS],
            _merkleProof: DynArray[DynArray[bytes32, MAX_PROOF_LENGTH], MAX_INTERVALS]): nonpayable
  def claimAndStake(_nodeAddress: address,
            _rewardIndex: DynArray[uint256, MAX_INTERVALS],
            _amountRPL: DynArray[uint256, MAX_INTERVALS],
            _amountETH: DynArray[uint256, MAX_INTERVALS],
            _merkleProof: DynArray[DynArray[bytes32, MAX_PROOF_LENGTH], MAX_INTERVALS],
            _stakeAmount: uint256): nonpayable
rocketMerkleDistributorKey: constant(bytes32) = keccak256("contract.addressrocketMerkleDistributorMainnet")

RPL: public(immutable(RPLInterface))
rocketStorage: public(immutable(RocketStorageInterface))

@external
def __init__():
  rocketStorage = RocketStorageInterface(0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46)
  RPL = RPLInterface(rocketStorage.getAddress(keccak256("contract.addressrocketTokenRPL")))

nextLenderId: public(uint256)

lenderAddress: public(HashMap[uint256, address])
pendingLenderAddress: public(HashMap[uint256, address])

struct PoolParams:
  lender: uint256
  feeNum: uint256
  feeDen: uint256
  endTime: uint256

params: public(HashMap[bytes32, PoolParams])

struct PoolState:
  supplied: uint256
  unclaimedETH: uint256
  unclaimedRPL: uint256

pools: public(HashMap[bytes32, PoolState])

# (poolId, nodeAddress): RPL borrowed
borrowed: public(HashMap[bytes32, HashMap[address, uint256]])
totalBorrowedFromPool: public(HashMap[bytes32, uint256])
totalBorrowedByNode: public(HashMap[address, uint256])

# nodeAddress: the node's next withdrawal address (using this contract as the first withdrawal address)
borrowerAddress: public(HashMap[address, address])
pendingBorrowerAddress: public(HashMap[address, address])

# nodeAddress: amounts unclaimed by borrowerAddress[nodeAddress]
unclaimedETH: public(HashMap[address, uint256])
unclaimedRPL: public(HashMap[address, uint256])
# nodeAddress: amount of staked RPL belonging wholly to the borrower, not borrowed from any of our pools
#              (when we can determine this has been unstaked, we move the unstaked portion to unclaimedRPL)
borrowerRPL: public(HashMap[address, uint256])
# nodeAddress: next rewards interval index we need to account for for this node
#              (all Merkle rewards claims that include any funds belonging to our pools
#               have been claimed and processed by us up to but not including this index)
accountingInterval: public(HashMap[address, uint256])

@external
def registerLender() -> uint256:
  id: uint256 = self.nextLenderId
  self.lenderAddress[id] = msg.sender
  self.nextLenderId = id + 1
  # TODO: event
  return id

@internal
def _updateLenderAddress(_lender: uint256, _newAddress: address):
  self.pendingLenderAddress[_lender] = empty(address)
  self.lenderAddress[_lender] = _newAddress
  # TODO: event

@external
def changeLenderAddress(_lender: uint256, _newAddress: address, _confirm: bool):
  assert msg.sender == self.lenderAddress[_lender], "auth"
  if _confirm:
    self._updateLenderAddress(_lender, _newAddress)
  else:
    self.pendingLenderAddress[_lender] = _newAddress

@external
def confirmChangeLenderAddress(_lender: uint256):
  assert msg.sender == self.pendingLenderAddress[_lender], "auth"
  self._updateLenderAddress(_lender, msg.sender)

# poolId is unique for a lender, fee fraction, and end time
@internal
def _poolId(_params: PoolParams) -> bytes32:
  return keccak256(concat(
                     convert(_params.lender, bytes32),
                     convert(_params.feeNum, bytes32),
                     convert(_params.feeDen, bytes32),
                     convert(_params.endTime, bytes32)
                  ))

@external
def createPool(_params: PoolParams) -> bytes32:
  assert msg.sender == self.lenderAddress[_params.lender], "auth"
  poolId: bytes32 = self._poolId(_params)
  # TODO: event
  return poolId

@internal
def _checkFromLender(_poolId: bytes32):
  assert msg.sender == self.lenderAddress[self.params[_poolId].lender], "auth"

# TODO: use withdrawal fee instead of supply fee, and make it to a protocol address

@internal
def _supply(_poolId: bytes32, _amount: uint256, _feeAmount: uint256, _feeRecipient: address):
  assert _feeAmount * 100 <= _amount * MAX_FEE_PERCENT, "fee"
  supplyAmount: uint256 = _amount - _feeAmount
  assert RPL.transferFrom(msg.sender, self, supplyAmount), "stf"
  assert RPL.transferFrom(msg.sender, _feeRecipient, _feeAmount), "ftf"
  self.pools[_poolId].supplied += supplyAmount
  # TODO: event

# lender can supply RPL to one of their pools
@external
def supply(_poolId: bytes32, _amount: uint256, _feeAmount: uint256, _feeRecipient: address):
  self._checkFromLender(_poolId)
  self._supply(_poolId, _amount, _feeAmount, _feeRecipient)

# supply RPL to a pool from another address
@external
def supplyOnBehalf(_poolId: bytes32, _amount: uint256, _feeAmount: uint256, _feeRecipient: address):
  self._supply(_poolId, _amount, _feeAmount, _feeRecipient)

# lender can withdraw supplied RPL after the end time (assuming the loan has been repaid)
@external
def withdraw(_poolId: bytes32):
  self._checkFromLender(_poolId)
  assert self.params[_poolId].endTime <= block.timestamp, "term"
  assert self.totalBorrowedFromPool[_poolId] == 0, "debt"
  assert RPL.transfer(msg.sender, self.pools[_poolId].supplied), "t"
  self.pools[_poolId].supplied = 0
  # TODO: event

# lender can withdraw supplied RPL that has not been borrowed, possibly before the end time
@external
def withdrawExcess(_poolId: bytes32, _amount: uint256):
  self._checkFromLender(_poolId)
  assert _amount <= self.pools[_poolId].supplied - self.totalBorrowedFromPool[_poolId], "bal"
  assert RPL.transfer(msg.sender, _amount), "t"
  self.pools[_poolId].supplied -= _amount
  # TODO: event

# TODO: add optional pathways for claiming funds via withdrawal address:
# TODO: - claim merkle rewards (take fees)
# TODO: - distribute fee distributor balance (take fees)
# TODO: - distribute minipool balances (allocate stake to borrower, take fees on the rest)
# TODO: function to indicate that merkle rewards have been claimed, if not claimed via this contract (take fees)
# TODO: function to withdraw borrower RPL

# TODO: accounting for proportion of staked RPL, including as it changes, for fee calculation

@internal
def _getRocketNodeStaking() -> RocketNodeStakingInterface:
  return RocketNodeStakingInterface(
    rocketStorage.getAddress(rocketNodeStakingKey)
  )

@internal
def _getRocketNodeManager() -> RocketNodeManagerInterface:
  return RocketNodeManagerInterface(
    rocketStorage.getAddress(rocketNodeManagerKey)
  )

@internal
def _getMerkleDistributor() -> RocketMerkleDistributorInterface:
  return RocketMerkleDistributorInterface(
    rocketStorage.getAddress(rocketMerkleDistributorKey)
  )

@internal
def _getRewardsPool() -> RocketRewardsPoolInterface:
  return RocketRewardsPoolInterface(
    rocketStorage.getAddress(rocketRewardsPoolKey)
  )

# anyone can confirm this contract as a node's withdrawal address
# sets the borrower's withdrawal address as the node's withdrawal address prior to this contract
# also sets this contract as the node's RPL withdrawal address
# reverts unless the node has set this contract as its pending withdrawal address
# and does not already have an RPL withdrawal address set
@external
def confirmWithdrawalAddress(_node: address):
  assert not rocketStorage.getBool(
    keccak256(concat(b"node.stake.for.allowed",
                     convert(_node, bytes20),
                     convert(self, bytes20)))), "sfa"
  self.borrowerAddress[_node] = rocketStorage.getNodeWithdrawalAddress(_node)
  rocketStorage.confirmWithdrawalAddress(_node)
  self._getRocketNodeManager().setRPLWithdrawalAddress(_node, self, True)
  self.borrowerRPL[_node] = self._getRocketNodeStaking().getNodeRPLStake(_node)
  self.accountingInterval[_node] = self._getRewardsPool().getRewardIndex()
  # TODO: event

@internal
def _updateBorrowerAddress(_node: address, _newAddress: address):
  self.pendingBorrowerAddress[_node] = empty(address)
  self.borrowerAddress[_node] = _newAddress
  # TODO: event

# a borrower can change their withdrawal address for this contract
@external
def changeBorrowerAddress(_node: address, _newAddress: address, _confirm: bool):
  assert msg.sender == self.borrowerAddress[_node], "auth"
  if _confirm:
    self._updateBorrowerAddress(_node, _newAddress)
  else:
    self.pendingBorrowerAddress[_node] = _newAddress

@external
def confirmChangeBorrowerAddress(_node: address):
  assert msg.sender == self.pendingBorrowerAddress[_node], "auth"
  self._updateBorrowerAddress(_node, msg.sender)

# lender can claim any unclaimed rewards that have arrived in this contract
# (which is the withdrawal address for borrowing nodes)
@external
def claimLenderRewards(_poolId: bytes32):
  self._checkFromLender(_poolId)
  if 0 < self.pools[_poolId].unclaimedRPL:
    assert RPL.transfer(msg.sender, self.pools[_poolId].unclaimedRPL), "t"
    self.pools[_poolId].unclaimedRPL = 0
  if 0 < self.pools[_poolId].unclaimedETH:
    send(msg.sender, self.pools[_poolId].unclaimedETH, gas=msg.gas)
    self.pools[_poolId].unclaimedETH = 0
  # TODO: event

@external
def borrow(_poolId: bytes32, _amount: uint256, _node: address):
  assert _amount + self.totalBorrowedFromPool[_poolId] <= self.pools[_poolId].supplied, "bal"
  assert rocketStorage.getNodeWithdrawalAddress(_node) == self, "pwa"
  assert self._getRocketNodeManager().getNodeRPLWithdrawalAddressIsSet(_node), "rws"
  # the commented out assert is unnecessary since stakeRPLFor will fail otherwise
  # rocketNodeManager: RocketNodeManagerInterface = self._getRocketNodeManager()
  # assert rocketNodeManager.getNodeRPLWithdrawalAddress(_node) == self, "rwa"
  self._getRocketNodeStaking().stakeRPLFor(_node, _amount)
  self.borrowed[_poolId][_node] += _amount
  self.totalBorrowedFromPool[_poolId] += _amount
  self.totalBorrowedByNode[_node] += _amount
  # TODO: event

# ETH that goes to the lender is based on the pool fee
# RPL that goes to the lender is proportional to the amount the node borrowed vs its total RPL stake

@external
def repay(_poolId: bytes32, _node: address, _amount: uint256, _amountSupplied: uint256):
  assert _amount == 0 or msg.sender == self.borrowerAddress[_node], "auth"
  total: uint256 = _amount + _amountSupplied
  assert total <= self.totalBorrowedByNode[_node], "balb"
  rocketNodeStaking: RocketNodeStakingInterface = self._getRocketNodeStaking()
  stakedRPL: uint256 = rocketNodeStaking.getNodeRPLStake(_node)
  assert _amount <= stakedRPL, "bals"
  if stakedRPL > self.borrowerRPL[_node] + self.totalBorrowedByNode[_node]:
    # someone else must have staked RPL on behalf of the node
    # return the excess to the borrower (TODO: we or the lender could take a cut of this?)
    self.borrowerRPL[_node] = stakedRPL - self.totalBorrowedByNode[_node]
  # TODO: handle case of RPL slashed
  if 0 < _amount:
    rocketNodeStaking.withdrawRPL(_node, _amount)
  if 0 < _amountSupplied:
    assert RPL.transferFrom(msg.sender, self, _amountSupplied), "tf"
  self.totalBorrowedByNode[_node] -= total
  self.totalBorrowedFromPool[_poolId] -= total
  # TODO: event

@external
def claimBorrowerRewards(_node: address):
  assert msg.sender == self.borrowerAddress[_node], "auth"
  if 0 < self.unclaimedRPL[_node]:
    assert RPL.transfer(msg.sender, self.unclaimedRPL[_node]), "t"
    self.unclaimedRPL[_node] = 0
  if 0 < self.unclaimedETH[_node]:
    send(msg.sender, self.unclaimedETH[_node], gas=msg.gas)
    self.unclaimedETH[_node] = 0
  # TODO: event

@internal
def _checkFinished(_node: address):
  assert msg.sender == _node or msg.sender == self.borrowerAddress[_node], "auth"
  assert self.totalBorrowedByNode[_node] == 0, "debt"

@external
def changeWithdrawalAddress(_node: address, _newAddress: address, _confirm: bool):
  self._checkFinished(_node)
  rocketStorage.setWithdrawalAddress(_node, _newAddress, _confirm)

@external
def changeRPLWithdrawalAddress(_node: address, _newAddress: address, _confirm: bool):
  self._checkFinished(_node)
  self._getRocketNodeManager().setRPLWithdrawalAddress(_node, _newAddress, _confirm)

@external
def unsetRPLWithdrawalAddress(_node: address):
  self._checkFinished(_node)
  self._getRocketNodeManager().unsetRPLWithdrawalAddress(_node)
