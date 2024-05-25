#pragma version ^0.3.0

interface RPLInterface:
  def decimals() -> uint8: view
  def transfer(_to: address, _value: uint256) -> bool: nonpayable
  def transferFrom(_from: address, _to: address, _value: uint256) -> bool: nonpayable
  def approve(_spender: address, _value: uint256) -> bool: nonpayable

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

MAX_TOTAL_INTERVALS: constant(uint256) = 2048 # 170+ years
MAX_CLAIM_INTERVALS: constant(uint256) = 128 # ~10 years
MAX_PROOF_LENGTH: constant(uint256) = 32 # ~ 4 billion claimers
MAX_FEE_PERCENT: constant(uint256) = 25

interface RocketMerkleDistributorInterface:
  def isClaimed(_rewardIndex: uint256, _nodeAddress: address) -> bool: view
  def claim(_nodeAddress: address,
            _rewardIndex: DynArray[uint256, MAX_CLAIM_INTERVALS],
            _amountRPL: DynArray[uint256, MAX_CLAIM_INTERVALS],
            _amountETH: DynArray[uint256, MAX_CLAIM_INTERVALS],
            _merkleProof: DynArray[DynArray[bytes32, MAX_PROOF_LENGTH], MAX_CLAIM_INTERVALS]): nonpayable
  def claimAndStake(_nodeAddress: address,
            _rewardIndex: DynArray[uint256, MAX_CLAIM_INTERVALS],
            _amountRPL: DynArray[uint256, MAX_CLAIM_INTERVALS],
            _amountETH: DynArray[uint256, MAX_CLAIM_INTERVALS],
            _merkleProof: DynArray[DynArray[bytes32, MAX_PROOF_LENGTH], MAX_CLAIM_INTERVALS],
            _stakeAmount: uint256): nonpayable
rocketMerkleDistributorKey: constant(bytes32) = keccak256("contract.addressrocketMerkleDistributorMainnet")

RPL: public(immutable(RPLInterface))
rocketStorage: public(immutable(RocketStorageInterface))

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

struct ProtocolState:
  fees: uint256 # RPL owed to the protocol (not yet claimed)
  feePercent: uint256 # current protocol fee rate
  address: address
  pending: address

protocol: public(ProtocolState)

nextLenderId: public(uint256)

lenderAddress: public(HashMap[uint256, address])
pendingLenderAddress: public(HashMap[uint256, address])

struct PoolParams:
  lender: uint256
  interestRate: uint256 # attoRPL per RPL borrowed per second (before loan end time)
  endTime: uint256 # seconds after Unix epoch

params: public(HashMap[bytes32, PoolParams])

struct PoolState:
  available: uint256 # RPL available to be returned to the lender
  borrowed: uint256 # total RPL currently borrowed by borrowers
  interest: uint256 # total accrued interest, not including on borrowed
  reclaimed: uint256 # ETH accrued (not yet returned to lender) in service of defaults

pools: public(HashMap[bytes32, PoolState])

struct LoanState:
  borrowed: uint256 # RPL currently borrowed
  startTime: uint256 # start time for ongoing interest accumulation on borrowed
  interest: uint256 # interest already accumulated (and not yet paid)

loans: public(HashMap[bytes32, HashMap[address, LoanState]])

struct BorrowerState:
  borrowed: uint256 # total RPL borrowed
  interest: uint256 # interest accumulated (and not yet paid), not including ongoing
  RPL: uint256 # RPL available for repayments and/or withdrawal
  ETH: uint256 # ETH available for liquidation and/or withdrawal
  index: uint256 # first not-yet-accounted interval index
  address: address # current address for the borrower
  pending: address # potential future address for the borrower

borrowers: public(HashMap[address, BorrowerState])
intervals: public(HashMap[address, HashMap[uint256, bool]]) # intervals known to be claimed (up to borrowers[_].index)

oneRPL: immutable(uint256)

@external
def __init__():
  rocketStorage = RocketStorageInterface(0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46)
  RPL = RPLInterface(rocketStorage.getAddress(keccak256("contract.addressrocketTokenRPL")))
  self.protocol.address = msg.sender
  oneRPL = 10 ** convert(RPL.decimals(), uint256)

allowPaymentsFrom: address
@external
@payable
def __default__():
  assert msg.sender == self.allowPaymentsFrom, "auth"

# Protocol actions

event UpdateAdmin:
  old: indexed(address)
  new: indexed(address)

event UpdateFeePercent:
  old: indexed(uint256)
  new: indexed(uint256)

event WithdrawFees:
  recipient: indexed(address)
  amount: indexed(uint256)

@internal
def _updateAdminAddress(_newAddress: address):
  self.protocol.pending = empty(address)
  log UpdateAdmin(self.protocol.address, _newAddress)
  self.protocol.address = _newAddress

@external
def changeAdminAddress(_newAddress: address, _confirm: bool):
  assert msg.sender == self.protocol.address, "auth"
  if _confirm:
    self._updateAdminAddress(_newAddress)
  else:
    self.protocol.pending = _newAddress

@external
def confirmChangeAdminAddress():
  assert msg.sender == self.protocol.pending, "auth"
  self._updateAdminAddress(msg.sender)

@external
def updateFeePercent(_newPercent: uint256):
  assert msg.sender == self.protocol.address, "auth"
  assert _newPercent <= MAX_FEE_PERCENT, "max"
  log UpdateFeePercent(self.protocol.feePercent, _newPercent)
  self.protocol.feePercent = _newPercent

@external
def withdrawFees():
  assert msg.sender == self.protocol.address, "auth"
  assert RPL.transfer(msg.sender, self.protocol.fees), "t"
  log WithdrawFees(msg.sender, self.protocol.fees)
  self.protocol.fees = 0

# Lender actions

event RegisterLender:
  id: indexed(uint256)
  address: indexed(address)

event UpdateLender:
  id: indexed(uint256)
  old: indexed(address)
  new: indexed(address)

event CreatePool:
  id: indexed(bytes32)
  params: PoolParams

event SupplyPool:
  id: indexed(bytes32)
  amount: indexed(uint256)
  total: indexed(uint256)

event WithdrawFromPool:
  id: indexed(bytes32)
  amount: indexed(uint256)
  total: indexed(uint256)

event WithdrawEtherFromPool:
  id: indexed(bytes32)
  amount: indexed(uint256)
  total: indexed(uint256)

@external
def registerLender() -> uint256:
  id: uint256 = self.nextLenderId
  self.lenderAddress[id] = msg.sender
  self.nextLenderId = id + 1
  log RegisterLender(id, msg.sender)
  return id

@internal
def _updateLenderAddress(_lender: uint256, _newAddress: address):
  self.pendingLenderAddress[_lender] = empty(address)
  log UpdateLender(_lender, self.lenderAddress[_lender], _newAddress)
  self.lenderAddress[_lender] = _newAddress

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

@internal
def _poolId(_params: PoolParams) -> bytes32:
  return keccak256(concat(
                     convert(_params.lender, bytes32),
                     convert(_params.interestRate, bytes32),
                     convert(_params.endTime, bytes32)
                  ))

@external
def createPool(_params: PoolParams) -> bytes32:
  assert msg.sender == self.lenderAddress[_params.lender], "auth"
  poolId: bytes32 = self._poolId(_params)
  log CreatePool(poolId, _params)
  return poolId

@internal
def _checkFromLender(_poolId: bytes32):
  assert msg.sender == self.lenderAddress[self.params[_poolId].lender], "auth"

@internal
def _supplyPool(_poolId: bytes32, _amount: uint256):
  assert RPL.transferFrom(msg.sender, self, _amount), "tf"
  self.pools[_poolId].available += _amount
  log SupplyPool(_poolId, _amount, self.pools[_poolId].available)

@external
def supplyPool(_poolId: bytes32, _amount: uint256):
  self._checkFromLender(_poolId)
  self._supplyPool(_poolId, _amount)

@external
def supplyPoolOnBehalf(_poolId: bytes32, _amount: uint256):
  self._supplyPool(_poolId, _amount)

@external
def withdrawFromPool(_poolId: bytes32, _amount: uint256):
  self._checkFromLender(_poolId)
  self.pools[_poolId].available -= _amount
  assert RPL.transfer(msg.sender, _amount), "t"
  log WithdrawFromPool(_poolId, _amount, self.pools[_poolId].available)

# TODO: liquidation actions for RPL and ETH

@external
def withdrawEtherFromPool(_poolId: bytes32, _amount: uint256):
  self._checkFromLender(_poolId)
  self.pools[_poolId].reclaimed -= _amount
  send(msg.sender, _amount, gas=msg.gas)
  log WithdrawEtherFromPool(_poolId, _amount, self.pools[_poolId].reclaimed)

# Borrower actions

@internal
def _checkFromBorrower(_node: address):
  assert msg.sender == self.borrowers[_node].address, "auth"

@internal
def _updateBorrowerAddress(_node: address, _newAddress: address):
  self.borrowers[_node].pending = empty(address)
  self.borrowers[_node].address = _newAddress
  # TODO: event

@external
def changeBorrowerAddress(_node: address, _newAddress: address, _confirm: bool):
  self._checkFromBorrower(_node)
  if _confirm:
    self._updateBorrowerAddress(_node, _newAddress)
  else:
    self.borrowers[_node].pending = _newAddress

@external
def confirmChangeBorrowerAddress(_node: address):
  assert msg.sender == self.borrowers[_node].pending, "auth"
  self._updateBorrowerAddress(_node, msg.sender)

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

  if self.borrowers[_node].address == empty(address):
    self.borrowers[_node].address = rocketStorage.getNodeWithdrawalAddress(_node)

  rocketStorage.confirmWithdrawalAddress(_node)
  self._getRocketNodeManager().setRPLWithdrawalAddress(_node, self, True)

  rocketMerkleDistributor: RocketMerkleDistributorInterface = self._getMerkleDistributor()
  currentIndex: uint256 = self._getRewardsPool().getRewardIndex()
  index: uint256 = self.borrowers[_node].index
  for _ in range(MAX_TOTAL_INTERVALS):
    if currentIndex <= index: break
    self.intervals[_node][index] = rocketMerkleDistributor.isClaimed(index, _node)
    index += 1
  self.borrowers[_node].index = index
  # TODO: event

@internal
def _checkFinished(_node: address):
  assert msg.sender == _node or msg.sender == self.borrowers[_node].address, "auth"
  assert self.borrowers[_node].borrowed == 0, "b"
  assert self.borrowers[_node].interest == 0, "i"

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

@internal
def _stakeRPLFor(_node: address, _amount: uint256):
  rocketNodeStaking: RocketNodeStakingInterface = self._getRocketNodeStaking()
  assert RPL.approve(rocketNodeStaking.address, _amount), "a"
  rocketNodeStaking.stakeRPLFor(_node, _amount)

@external
def stakeRPLFor(_node: address, _amount: uint256):
  self._checkFromBorrower(_node)
  self._stakeRPLFor(_node, _amount)

@external
def withdrawRPL(_node: address, _amount: uint256):
  self._checkFromBorrower(_node)
  self._getRocketNodeStaking().withdrawRPL(_node, _amount)
  self.borrowers[_node].RPL += _amount
  # TODO: event?

@internal
@view
def _effectiveEndTime(_poolId: bytes32) -> uint256:
  return min(self.params[_poolId].endTime, block.timestamp)

@internal
@view
def _outstandingInterest(_poolId: bytes32, _node: address, _endTime: uint256) -> uint256:
  return (self.loans[_poolId][_node].borrowed
          * self.params[_poolId].interestRate
          * (_endTime - self.loans[_poolId][_node].startTime)
          / oneRPL)

@internal
def _chargeInterest(_poolId: bytes32, _node: address, _amount: uint256):
  if 0 < _amount:
    self.loans[_poolId][_node].interest += _amount
    self.borrowers[_node].interest += _amount
    self.pools[_poolId].interest += _amount

@internal
def _repayInterest(_poolId: bytes32, _node: address, _amount: uint256) -> uint256:
  if 0 < _amount:
    self.loans[_poolId][_node].interest -= _amount
    self.borrowers[_node].interest -= _amount
    self.pools[_poolId].interest -= _amount
  return _amount

@internal
def _lend(_poolId: bytes32, _node: address, _amount: uint256):
  if 0 < _amount:
    self.loans[_poolId][_node].borrowed += _amount
    self.borrowers[_node].borrowed += _amount
    self.pools[_poolId].available -= _amount
    self.pools[_poolId].borrowed += _amount

@internal
def _repay(_poolId: bytes32, _node: address, _amount: uint256) -> uint256:
  if 0 < _amount:
    self.loans[_poolId][_node].borrowed -= _amount
    self.borrowers[_node].borrowed -= _amount
    self.pools[_poolId].available += _amount
    self.pools[_poolId].borrowed -= _amount
    # TODO: charge protocol fee here
  return _amount

@external
def borrow(_poolId: bytes32, _amount: uint256, _node: address):
  assert rocketStorage.getNodeWithdrawalAddress(_node) == self, "pwa"
  assert self._getRocketNodeManager().getNodeRPLWithdrawalAddressIsSet(_node), "rws"
  # the commented out assert is unnecessary since stakeRPLFor will fail otherwise
  # rocketNodeManager: RocketNodeManagerInterface = self._getRocketNodeManager()
  # assert rocketNodeManager.getNodeRPLWithdrawalAddress(_node) == self, "rwa"
  assert block.timestamp < self.params[_poolId].endTime, "end"
  self._stakeRPLFor(_node, _amount)
  self._chargeInterest(_poolId, _node, self._outstandingInterest(_poolId, _node, block.timestamp))
  self.loans[_poolId][_node].startTime = block.timestamp
  self._lend(_poolId, _node, _amount)
  # TODO: event

@external
def repay(_poolId: bytes32, _node: address, _amount: uint256, _amountSupplied: uint256):
  assert _amount == 0 or msg.sender == self.borrowers[_node].address, "auth"
  endTime: uint256 = self._effectiveEndTime(_poolId)
  self._chargeInterest(_poolId, _node, self._outstandingInterest(_poolId, _node, endTime))
  self.loans[_poolId][_node].startTime = endTime
  rocketNodeStaking: RocketNodeStakingInterface = self._getRocketNodeStaking()
  available: uint256 = 0
  if self.borrowers[_node].RPL < _amount:
    rocketNodeStaking.withdrawRPL(_node, _amount - self.borrowers[_node].RPL)
    self.borrowers[_node].RPL = _amount
  self.borrowers[_node].RPL -= _amount
  available += _amount
  if 0 < _amountSupplied:
    assert RPL.transferFrom(msg.sender, self, _amountSupplied), "tf"
    available += _amountSupplied
  if available <= self.loans[_poolId][_node].interest:
    available -= self._repayInterest(_poolId, _node, available)
  else:
    available -= self._repayInterest(_poolId, _node, self.loans[_poolId][_node].interest)
    available -= self._repay(_poolId, _node, available)
  assert available == 0, "bal"
  # TODO: event
