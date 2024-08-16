#pragma version ~=0.4.0
#pragma evm-version cancun
#pragma optimize gas

MAX_TOTAL_INTERVALS: constant(uint256) = 2048 # 170+ years
MAX_CLAIM_INTERVALS: constant(uint256) = 128 # ~10 years
MAX_PROOF_LENGTH: constant(uint256) = 32 # ~ 4 billion claimers
MAX_NODE_MINIPOOLS: constant(uint256) = 2048
MAX_ADDRESS_BATCH: constant(uint256) = 2048
BORROW_LIMIT_PERCENT: constant(uint256) = 50
SECONDS_PER_YEAR: constant(uint256) = 365 * 24 * 60 * 60

ensRegistry: constant(address) = 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e
addrReverseNode: constant(bytes32) = 0x91d1777781884d03a6757a803996e38de2a42967fb37eeaca72729271025a9e2
interface registryInterface:
  def owner(_node: bytes32) -> address: view
interface reverseRegistrarInterface:
  def setName(_name: String[16]) -> bytes32: nonpayable
@external
def setName():
  extcall reverseRegistrarInterface(
    staticcall registryInterface(ensRegistry).owner(addrReverseNode)
  ).setName("rocketlend.eth")

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

interface RocketNodeDepositInterface:
  def depositEthFor(_nodeAddress: address): payable
  def getNodeEthBalance(_nodeAddress: address) -> uint256: view
rocketNodeDepositKey: constant(bytes32) = keccak256("contract.addressrocketNodeDeposit")

interface RocketNodeStakingInterface:
  def getNodeRPLStake(_nodeAddress: address) -> uint256: view
  def getNodeETHProvided(_nodeAddress: address) -> uint256: view
  def stakeRPLFor(_nodeAddress: address, _amount: uint256): nonpayable
  def withdrawRPL(_nodeAddress: address, _amount: uint256): nonpayable
  def getRPLLockingAllowed(_nodeAddress: address) -> bool: view
  def setRPLLockingAllowed(_nodeAddress: address, _allowed: bool): nonpayable
rocketNodeStakingKey: constant(bytes32) = keccak256("contract.addressrocketNodeStaking")

interface RocketRewardsPoolInterface:
  def getRewardIndex() -> uint256: view
rocketRewardsPoolKey: constant(bytes32) = keccak256("contract.addressrocketRewardsPool")

interface RocketNetworkPricesInterface:
  def getRPLPrice() -> uint256: view
rocketNetworkPricesKey: constant(bytes32) = keccak256("contract.addressrocketNetworkPrices")

interface RocketMerkleDistributorInterface:
  def isClaimed(_rewardIndex: uint256, _nodeAddress: address) -> bool: view
  def claimAndStake(_nodeAddress: address,
            _rewardIndex: DynArray[uint256, MAX_CLAIM_INTERVALS],
            _amountRPL: DynArray[uint256, MAX_CLAIM_INTERVALS],
            _amountETH: DynArray[uint256, MAX_CLAIM_INTERVALS],
            _merkleProof: DynArray[DynArray[bytes32, MAX_PROOF_LENGTH], MAX_CLAIM_INTERVALS],
            _stakeAmount: uint256): nonpayable
rocketMerkleDistributorKey: constant(bytes32) = keccak256("contract.addressrocketMerkleDistributorMainnet")

interface RocketNodeDistributorFactoryInterface:
  def getProxyAddress(_nodeAddress: address) -> address: view
rocketNodeDistributorFactoryKey: constant(bytes32) = keccak256("contract.addressrocketNodeDistributorFactory")

interface RocketNodeDistributorInterface:
  def getNodeShare() -> uint256: view
  def distribute(): nonpayable

interface MinipoolInterface:
  def distributeBalance(_rewardsOnly: bool): nonpayable
  def refund(): nonpayable

RPL: public(immutable(RPLInterface))
rocketStorage: public(immutable(RocketStorageInterface))

@internal
@view
def _getRocketNodeStaking() -> RocketNodeStakingInterface:
  return RocketNodeStakingInterface(
    staticcall rocketStorage.getAddress(rocketNodeStakingKey)
  )

@internal
@view
def _getRocketNodeDeposit() -> RocketNodeDepositInterface:
  return RocketNodeDepositInterface(
    staticcall rocketStorage.getAddress(rocketNodeDepositKey)
  )

@internal
@view
def _getRocketNodeManager() -> RocketNodeManagerInterface:
  return RocketNodeManagerInterface(
    staticcall rocketStorage.getAddress(rocketNodeManagerKey)
  )

@internal
@view
def _getMerkleDistributor() -> RocketMerkleDistributorInterface:
  return RocketMerkleDistributorInterface(
    staticcall rocketStorage.getAddress(rocketMerkleDistributorKey)
  )

@internal
@view
def _getRewardsPool() -> RocketRewardsPoolInterface:
  return RocketRewardsPoolInterface(
    staticcall rocketStorage.getAddress(rocketRewardsPoolKey)
  )

@internal
@view
def _getRocketNetworkPrices() -> RocketNetworkPricesInterface:
  return RocketNetworkPricesInterface(
    staticcall rocketStorage.getAddress(rocketNetworkPricesKey)
  )

@internal
@view
def _getNodeDistributor(_node: address) -> RocketNodeDistributorInterface:
  return RocketNodeDistributorInterface(
    staticcall RocketNodeDistributorFactoryInterface(
      staticcall rocketStorage.getAddress(rocketNodeDistributorFactoryKey)
    ).getProxyAddress(_node)
  )

nextLenderId: public(uint256)

lenderAddress: public(HashMap[uint256, address])
pendingLenderAddress: public(HashMap[uint256, address])

struct PoolParams:
  lender: uint256
  interestRate: uint256 # whole number percentage APR
  endTime: uint256 # seconds after Unix epoch

params: public(HashMap[bytes32, PoolParams])

struct PoolState:
  available: uint256 # RPL available to be returned to the lender
  borrowed: uint256 # total RPL currently borrowed by borrowers
  allowance: uint256 # limit on RPL that can be made available by transferring borrowed from another of this lender's pools (or interest from another loan)
  interestPaid: uint256 # interest paid to the pool (not yet claimed by lender)
  reclaimed: uint256 # ETH accrued (not yet returned to lender) in service of defaults

pools: public(HashMap[bytes32, PoolState])

allowedToBorrow: public(HashMap[bytes32, HashMap[address, bool]])

struct LoanState:
  borrowed: uint256 # RPL currently borrowed
  startTime: uint256 # start time for ongoing interest accumulation on borrowed
  interestDue: uint256 # interest already accumulated (and not yet paid)

loans: public(HashMap[bytes32, HashMap[address, LoanState]])

struct BorrowerState:
  borrowed: uint256 # total RPL borrowed
  interestDue: uint256 # interest accumulated (and not yet paid), not including ongoing
  RPL: uint256 # RPL available for repayments and/or withdrawal
  ETH: uint256 # ETH available for liquidation and/or withdrawal
  index: uint256 # first not-yet-accounted interval index
  address: address # current address for the borrower
  pending: address # potential future address for the borrower

borrowers: public(HashMap[address, BorrowerState])
intervals: public(HashMap[address, HashMap[uint256, bool]]) # intervals known to be claimed (up to borrowers[_].index)

oneRPL: immutable(uint256)
oneEther: constant(uint256) = 10 ** 18

@deploy
def __init__(_rocketStorage: address):
  rocketStorage = RocketStorageInterface(_rocketStorage)
  RPL = RPLInterface(staticcall rocketStorage.getAddress(keccak256("contract.addressrocketTokenRPL")))
  oneRPL = 10 ** convert(staticcall RPL.decimals(), uint256)

allowPaymentsFrom: address
@external
@payable
def __default__():
  assert msg.sender == self.allowPaymentsFrom, "auth"

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

event SetAllowance:
  id: indexed(bytes32)
  old: indexed(uint256)
  new: indexed(uint256)

event ChangeAllowedToBorrow:
  id: indexed(bytes32)
  allowed: indexed(bool)
  nodes: DynArray[address, MAX_ADDRESS_BATCH]

event WithdrawFromPool:
  id: indexed(bytes32)
  amount: indexed(uint256)
  total: indexed(uint256)

event WithdrawInterest:
  id: indexed(bytes32)
  amount: indexed(uint256)
  supplied: indexed(uint256)
  interestPaid: uint256
  available: uint256

event WithdrawEtherFromPool:
  id: indexed(bytes32)
  amount: indexed(uint256)
  total: indexed(uint256)

event ForceRepayRPL:
  id: indexed(bytes32)
  node: indexed(address)
  withdrawn: indexed(uint256)
  available: uint256
  borrowed: uint256
  interestDue: uint256

event ForceRepayETH:
  id: indexed(bytes32)
  node: indexed(address)
  amount: indexed(uint256)
  available: uint256
  borrowed: uint256
  interestDue: uint256

event ForceClaimRewards:
  id: indexed(bytes32)
  node: indexed(address)
  claimedRPL: uint256
  claimedETH: uint256
  repaidRPL: uint256
  repaidETH: uint256
  RPL: uint256
  ETH: uint256
  borrowed: uint256
  interestDue: uint256

event ForceDistributeRefund:
  id: indexed(bytes32)
  node: indexed(address)
  claimed: uint256
  repaid: uint256
  available: uint256
  borrowed: uint256
  interestDue: uint256

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
def createPool(_params: PoolParams, _andSupply: uint256, _allowance: uint256, _borrowers: DynArray[address, MAX_ADDRESS_BATCH]) -> bytes32:
  assert msg.sender == self.lenderAddress[_params.lender], "auth"
  poolId: bytes32 = self._poolId(_params)
  self.params[poolId] = _params
  log CreatePool(poolId, _params)
  if 0 < _andSupply:
    self._supplyPool(poolId, _andSupply)
  if 0 < _allowance:
    self._setAllowance(poolId, _allowance)
  for node: address in _borrowers:
    self.allowedToBorrow[poolId][node] = True
  log ChangeAllowedToBorrow(poolId, True, _borrowers)
  return poolId

@internal
@view
def _lenderAddress(_poolId: bytes32) -> address:
  return self.lenderAddress[self.params[_poolId].lender]

@internal
def _checkFromLender(_poolId: bytes32):
  assert msg.sender == self._lenderAddress(_poolId), "auth"

@internal
def _supplyPool(_poolId: bytes32, _amount: uint256):
  assert extcall RPL.transferFrom(msg.sender, self, _amount), "tf"
  self.pools[_poolId].available += _amount
  log SupplyPool(_poolId, _amount, self.pools[_poolId].available)

@external
def supplyPool(_poolId: bytes32, _amount: uint256):
  self._supplyPool(_poolId, _amount)

@internal
def _setAllowance(_poolId: bytes32, _amount: uint256):
  log SetAllowance(_poolId, self.pools[_poolId].allowance, _amount)
  self.pools[_poolId].allowance = _amount

@external
def setAllowance(_poolId: bytes32, _amount: uint256):
  self._checkFromLender(_poolId)
  self._setAllowance(_poolId, _amount)

@external
def changeAllowedToBorrow(_poolId: bytes32, _allowed: bool, _nodes: DynArray[address, MAX_ADDRESS_BATCH]):
  self._checkFromLender(_poolId)
  if _allowed:
    self.allowedToBorrow[_poolId][empty(address)] = False
  for node: address in _nodes:
    self.allowedToBorrow[_poolId][node] = _allowed
  log ChangeAllowedToBorrow(_poolId, _allowed, _nodes)

@external
def withdrawFromPool(_poolId: bytes32, _amount: uint256):
  self._checkFromLender(_poolId)
  self.pools[_poolId].available -= _amount
  assert extcall RPL.transfer(msg.sender, _amount), "t"
  log WithdrawFromPool(_poolId, _amount, self.pools[_poolId].available)

@external
def withdrawInterest(_poolId: bytes32, _amount: uint256, _andSupply: uint256):
  self._checkFromLender(_poolId)
  self.pools[_poolId].interestPaid -= _amount
  if _andSupply < _amount:
    assert extcall RPL.transfer(msg.sender, _amount - _andSupply), "t"
  self.pools[_poolId].available += _andSupply
  log WithdrawInterest(_poolId, _amount, _andSupply, self.pools[_poolId].interestPaid, self.pools[_poolId].available)

@external
def withdrawEtherFromPool(_poolId: bytes32, _amount: uint256):
  self._checkFromLender(_poolId)
  self.pools[_poolId].reclaimed -= _amount
  send(msg.sender, _amount, gas=msg.gas)
  log WithdrawEtherFromPool(_poolId, _amount, self.pools[_poolId].reclaimed)

@internal
def _checkEndedOwing(_poolId: bytes32, _node: address):
  endTime: uint256 = self.params[_poolId].endTime
  assert endTime < block.timestamp, "term"
  if self.loans[_poolId][_node].startTime < endTime:
    self._chargeInterest(_poolId, _node)
  assert 0 < self.loans[_poolId][_node].borrowed or 0 < self.loans[_poolId][_node].interestDue, "paid"

@external
def forceRepayRPL(_poolId: bytes32, _node: address, _withdrawAmount: uint256):
  self._checkEndedOwing(_poolId, _node)
  if 0 < _withdrawAmount:
    extcall self._getRocketNodeStaking().withdrawRPL(_node, _withdrawAmount)
    self.borrowers[_node].RPL += _withdrawAmount
  available: uint256 = self.borrowers[_node].RPL
  if 0 < _withdrawAmount:
    assert available <= self.loans[_poolId][_node].interestDue + self.loans[_poolId][_node].borrowed, "wd"
  available = self._payDebt(_poolId, _node, available)
  assert available < self.borrowers[_node].RPL, "none"
  self.borrowers[_node].RPL = available
  log ForceRepayRPL(_poolId, _node, _withdrawAmount, available, self.borrowers[_node].borrowed, self.borrowers[_node].interestDue)

@external
def forceRepayETH(_poolId: bytes32, _node: address):
  self._checkFromLender(_poolId)
  self._checkEndedOwing(_poolId, _node)
  ethPerRpl: uint256 = staticcall self._getRocketNetworkPrices().getRPLPrice()
  startAmount: uint256 = self.borrowers[_node].ETH
  amount: uint256 = startAmount - self._payDebt(_poolId, _node, startAmount // ethPerRpl) * ethPerRpl
  assert 0 < amount, "none"
  self.borrowers[_node].ETH -= amount
  self.pools[_poolId].reclaimed += amount
  log ForceRepayETH(_poolId, _node, amount, self.borrowers[_node].ETH, self.borrowers[_node].borrowed, self.borrowers[_node].interestDue)

@external
def forceClaimMerkleRewards(
      _poolId: bytes32,
      _node: address,
      _repayRPL: uint256,
      _repayETH: uint256,
      _rewardIndex: DynArray[uint256, MAX_CLAIM_INTERVALS],
      _amountRPL: DynArray[uint256, MAX_CLAIM_INTERVALS],
      _amountETH: DynArray[uint256, MAX_CLAIM_INTERVALS],
      _merkleProof: DynArray[DynArray[bytes32, MAX_PROOF_LENGTH], MAX_CLAIM_INTERVALS]
    ):
  if 0 < _repayETH:
    self._checkFromLender(_poolId)
  assert self.borrowers[_node].RPL < _repayRPL or self.borrowers[_node].ETH < _repayETH, "bal"
  self._checkEndedOwing(_poolId, _node)
  totalRPL: uint256 = 0
  totalETH: uint256 = 0
  totalRPL, totalETH = self._claimMerkleRewards(_node, _rewardIndex, _amountRPL, _amountETH, _merkleProof, 0)
  if 0 < _repayRPL:
    assert self._payDebt(_poolId, _node, _repayRPL) == 0, "RPL"
    self.borrowers[_node].RPL -= _repayRPL
  if 0 < _repayETH:
    ethPerRpl: uint256 = staticcall self._getRocketNetworkPrices().getRPLPrice()
    assert self._payDebt(_poolId, _node, _repayETH // ethPerRpl) == 0, "ETH"
    self.borrowers[_node].ETH -= _repayETH
    self.pools[_poolId].reclaimed += _repayETH
  log ForceClaimRewards(_poolId, _node, totalRPL, totalETH, _repayRPL, _repayETH,
                        self.borrowers[_node].RPL, self.borrowers[_node].ETH,
                        self.borrowers[_node].borrowed, self.borrowers[_node].interestDue)

@external
def forceDistributeRefund(_poolId: bytes32, _node: address,
                          _distribute: bool,
                          _distributeMinipools: DynArray[address, MAX_NODE_MINIPOOLS],
                          _rewardsOnly: bool,
                          _refundMinipools: DynArray[address, MAX_NODE_MINIPOOLS]):
  self._checkFromLender(_poolId)
  self._checkEndedOwing(_poolId, _node)
  total: uint256 = 0
  if _distribute:
    total += self._distribute(_node)
  total += self._distributeMinipools(_distributeMinipools, _rewardsOnly)
  total += self._refundMinipools(_refundMinipools)
  assert 0 < total, "none"
  ethPerRpl: uint256 = staticcall self._getRocketNetworkPrices().getRPLPrice()
  startAmount: uint256 = self.borrowers[_node].ETH
  amount: uint256 = startAmount - self._payDebt(_poolId, _node, startAmount // ethPerRpl) * ethPerRpl
  assert 0 < amount, "none"
  self.borrowers[_node].ETH -= amount
  self.pools[_poolId].reclaimed += amount
  log ForceDistributeRefund(_poolId, _node, total, amount, self.borrowers[_node].ETH,
                            self.borrowers[_node].borrowed, self.borrowers[_node].interestDue)

@internal
def _payDebt(_poolId: bytes32, _node: address, _amount: uint256) -> uint256:
  amount: uint256 = _amount
  if amount <= self.loans[_poolId][_node].interestDue:
    amount -= self._repayInterest(_poolId, _node, amount)
  else:
    amount -= self._repayInterest(_poolId, _node, self.loans[_poolId][_node].interestDue)
    amount -= self._repay(_poolId, _node, min(amount, self.loans[_poolId][_node].borrowed))
  return amount

# Borrower actions

event UpdateBorrower:
  node: indexed(address)
  old: indexed(address)
  new: indexed(address)

event JoinProtocol:
  node: indexed(address)

event LeaveProtocol:
  node: indexed(address)

event WithdrawRPL:
  node: indexed(address)
  amount: indexed(uint256)
  total: indexed(uint256)

event Borrow:
  pool: indexed(bytes32)
  node: indexed(address)
  amount: indexed(uint256)
  borrowed: uint256
  interestDue: uint256

event Repay:
  pool: indexed(bytes32)
  node: indexed(address)
  amount: indexed(uint256)
  borrowed: uint256
  interestDue: uint256

event TransferDebt:
  node: indexed(address)
  fromPool: indexed(bytes32)
  toPool: indexed(bytes32)
  amount: uint256
  interestDue: uint256
  allowance: uint256

event Distribute:
  node: indexed(address)
  amount: indexed(uint256)

event DistributeMinipools:
  node: indexed(address)
  amount: indexed(uint256)
  total: indexed(uint256)

event RefundMinipools:
  node: indexed(address)
  amount: indexed(uint256)
  total: indexed(uint256)

event ClaimRewards:
  node: indexed(address)
  claimedRPL: indexed(uint256)
  claimedETH: indexed(uint256)
  stakedRPL: uint256
  totalRPL: uint256
  totalETH: uint256
  index: uint256

event Withdraw:
  node: indexed(address)
  amountRPL: indexed(uint256)
  amountETH: indexed(uint256)
  totalRPL: uint256
  totalETH: uint256

event DepositETH:
  node: indexed(address)
  amount: indexed(uint256)
  total: indexed(uint256)

@internal
def _checkFromBorrower(_node: address):
  assert msg.sender == self.borrowers[_node].address, "auth"

@internal
def _updateBorrowerAddress(_node: address, _newAddress: address):
  self.borrowers[_node].pending = empty(address)
  log UpdateBorrower(_node, self.borrowers[_node].address, _newAddress)
  self.borrowers[_node].address = _newAddress

@external
def changeBorrowerAddress(_node: address, _newAddress: address, _confirm: bool):
  self._checkFromBorrower(_node)
  assert _newAddress != empty(address), "null"
  if _confirm:
    self._updateBorrowerAddress(_node, _newAddress)
  else:
    self.borrowers[_node].pending = _newAddress

@external
def confirmChangeBorrowerAddress(_node: address):
  assert msg.sender == self.borrowers[_node].pending, "auth"
  self._updateBorrowerAddress(_node, msg.sender)

@internal
def _updateIndex(_node: address, _toIndex: uint256):
  index: uint256 = self.borrowers[_node].index
  if _toIndex <= index: return
  rocketMerkleDistributor: RocketMerkleDistributorInterface = self._getMerkleDistributor()
  for _: uint256 in range(MAX_TOTAL_INTERVALS):
    if _toIndex <= index: break
    self.intervals[_node][index] = staticcall rocketMerkleDistributor.isClaimed(index, _node)
    index += 1
  self.borrowers[_node].index = index

@external
def joinAsBorrower(_node: address):
  assert self.borrowers[_node].address == empty(address), "j"
  assert not staticcall rocketStorage.getBool(
    keccak256(concat(b"node.stake.for.allowed",
                     convert(_node, bytes20),
                     convert(self, bytes20)))), "sfa"
  currentWithdrawalAddress: address = staticcall rocketStorage.getNodeWithdrawalAddress(_node)
  if currentWithdrawalAddress == self:
    assert msg.sender == _node, "auth"
    self.borrowers[_node].address = _node
  else:
    self.borrowers[_node].address = currentWithdrawalAddress
    extcall rocketStorage.confirmWithdrawalAddress(_node)
  extcall self._getRocketNodeManager().setRPLWithdrawalAddress(_node, self, True)
  rocketNodeStaking: RocketNodeStakingInterface = self._getRocketNodeStaking()
  if (staticcall rocketNodeStaking.getRPLLockingAllowed(_node)):
    extcall rocketNodeStaking.setRPLLockingAllowed(_node, False)
  self._updateIndex(_node, staticcall self._getRewardsPool().getRewardIndex())
  log JoinProtocol(_node)

@external
def leaveAsBorrower(_node: address):
  assert msg.sender == self.borrowers[_node].address, "auth"
  assert self.borrowers[_node].borrowed == 0, "b"
  assert self.borrowers[_node].interestDue == 0, "i"
  extcall rocketStorage.setWithdrawalAddress(_node, msg.sender, True)
  extcall self._getRocketNodeManager().unsetRPLWithdrawalAddress(_node)
  self.borrowers[_node].address = empty(address)
  log LeaveProtocol(_node)

@internal
def _stakeRPLFor(_node: address, _amount: uint256):
  rocketNodeStaking: RocketNodeStakingInterface = self._getRocketNodeStaking()
  assert extcall RPL.approve(rocketNodeStaking.address, _amount), "a"
  extcall rocketNodeStaking.stakeRPLFor(_node, _amount)

@external
def stakeRPLFor(_node: address, _amount: uint256):
  self._checkFromBorrower(_node)
  self._stakeRPLFor(_node, _amount)

@external
def withdrawRPL(_node: address, _amount: uint256):
  self._checkFromBorrower(_node)
  extcall self._getRocketNodeStaking().withdrawRPL(_node, _amount)
  self.borrowers[_node].RPL += _amount
  log WithdrawRPL(_node, _amount, self.borrowers[_node].RPL)

@internal
@view
def _outstandingInterest(_borrowed: uint256, _rate: uint256, _startTime: uint256, _endTime: uint256) -> uint256:
  # _rate is percentage RPL per RPL per Year
  return _borrowed * _rate * (_endTime - _startTime) // 100 // SECONDS_PER_YEAR

@internal
def _chargeInterest(_poolId: bytes32, _node: address):
  borrowed: uint256 = self.loans[_poolId][_node].borrowed
  startTime: uint256 = self.loans[_poolId][_node].startTime
  endTime: uint256 = self.params[_poolId].endTime
  rate: uint256 = self.params[_poolId].interestRate
  amount: uint256 = empty(uint256)
  if block.timestamp < endTime:
    amount += self._outstandingInterest(borrowed, rate, startTime, block.timestamp)
  elif startTime < endTime:
    amount += self._outstandingInterest(borrowed, rate, startTime, endTime)
    amount += self._outstandingInterest(borrowed, 2 * rate, endTime, block.timestamp)
  else:
    amount += self._outstandingInterest(borrowed, 2 * rate, startTime, block.timestamp)
  if 0 < amount:
    self.loans[_poolId][_node].interestDue += amount
    self.borrowers[_node].interestDue += amount
  self.loans[_poolId][_node].startTime = block.timestamp

@internal
def _repayInterest(_poolId: bytes32, _node: address, _amount: uint256) -> uint256:
  if 0 < _amount:
    self.loans[_poolId][_node].interestDue -= _amount
    self.borrowers[_node].interestDue -= _amount
    self.pools[_poolId].interestPaid += _amount
  return _amount

@internal
def _lend(_poolId: bytes32, _node: address, _amount: uint256):
  if 0 < _amount:
    assert (self.allowedToBorrow[_poolId][empty(address)] or
            self.allowedToBorrow[_poolId][_node]), "r"
    self.loans[_poolId][_node].borrowed += _amount
    self.borrowers[_node].borrowed += _amount
    self.pools[_poolId].available -= _amount
    self.pools[_poolId].borrowed += _amount

@internal
def _repay(_poolId: bytes32, _node: address, _amount: uint256) -> uint256:
  if 0 < _amount:
    self.loans[_poolId][_node].borrowed -= _amount
    self.borrowers[_node].borrowed -= _amount
    self.pools[_poolId].borrowed -= _amount
    self.pools[_poolId].available += _amount
  return _amount

@internal
@view
def _availableEther(_node: address) -> uint256:
  return (staticcall self._getRocketNodeStaking().getNodeETHProvided(_node)
          + staticcall self._getRocketNodeDeposit().getNodeEthBalance(_node)
          + self.borrowers[_node].ETH)

@internal
@view
def _borrowLimit(_node: address) -> uint256:
  return (self._availableEther(_node)
          * oneEther
          * BORROW_LIMIT_PERCENT
          // 100
          // staticcall self._getRocketNetworkPrices().getRPLPrice())

@internal
@view
def _debt(_node: address) -> uint256:
  return self.borrowers[_node].borrowed + self.borrowers[_node].interestDue

@internal
def _checkBorrowLimit(_node: address):
  assert self._debt(_node) <= self._borrowLimit(_node), "lim"

@internal
def _checkBorrowLimit2(_node: address):
  assert self._debt(_node) <= 2 * self._borrowLimit(_node), "lim"

@external
def borrow(_poolId: bytes32, _node: address, _amount: uint256):
  self._checkFromBorrower(_node)
  assert block.timestamp < self.params[_poolId].endTime, "end"
  self._stakeRPLFor(_node, _amount)
  self._chargeInterest(_poolId, _node)
  self._lend(_poolId, _node, _amount)
  self._checkBorrowLimit(_node)
  log Borrow(_poolId, _node, _amount,
             self.loans[_poolId][_node].borrowed,
             self.loans[_poolId][_node].interestDue)

@external
def repay(_poolId: bytes32, _node: address, _amount: uint256, _amountSupplied: uint256):
  assert _amount == 0 or msg.sender == self.borrowers[_node].address, "auth"
  self._chargeInterest(_poolId, _node)
  rocketNodeStaking: RocketNodeStakingInterface = self._getRocketNodeStaking()
  available: uint256 = 0
  if self.borrowers[_node].RPL < _amount:
    extcall rocketNodeStaking.withdrawRPL(_node, _amount - self.borrowers[_node].RPL)
    self.borrowers[_node].RPL = _amount
  if 0 < _amount:
    self.borrowers[_node].RPL -= _amount
    available += _amount
  if 0 < _amountSupplied:
    assert extcall RPL.transferFrom(msg.sender, self, _amountSupplied), "tf"
    available += _amountSupplied
  assert self._payDebt(_poolId, _node, available) == 0, "bal"
  log Repay(_poolId, _node, _amount + _amountSupplied,
            self.loans[_poolId][_node].borrowed,
            self.loans[_poolId][_node].interestDue)

@external
def transferDebt(_node: address, _fromPool: bytes32, _toPool: bytes32,
                 _fromAvailable: uint256, _fromInterest: uint256, _fromAllowance: uint256):
  if msg.sender != self.borrowers[_node].address:
    # not from borrower allowed only if:
    # from lender, after end time, to a pool of no greater interest rate
    assert (
      msg.sender == self._lenderAddress(_fromPool) and
      self.params[_fromPool].endTime < block.timestamp and
      self.params[_toPool].interestRate <= self.params[_fromPool].interestRate
    ), "auth"
  self._chargeInterest(_fromPool, _node)
  assert block.timestamp < self.params[_toPool].endTime, "end"
  if 0 < _fromAvailable:
    self._lend(_toPool, _node, _fromAvailable)
    self._payDebt(_fromPool, _node, _fromAvailable)
  if 0 < _fromAllowance:
    assert self.params[_fromPool].lender == self.params[_toPool].lender, "lender"
    self.pools[_toPool].allowance -= _fromAllowance
    self.loans[_fromPool][_node].borrowed -= _fromAllowance
    self.loans[_toPool][_node].borrowed += _fromAllowance
    self.pools[_fromPool].borrowed -= _fromAllowance
    self.pools[_toPool].borrowed += _fromAllowance
  if 0 < _fromInterest:
    assert self.params[_fromPool].lender == self.params[_toPool].lender, "lender"
    self.pools[_toPool].allowance -= _fromInterest
    self.loans[_fromPool][_node].interestDue -= _fromInterest
    self.loans[_toPool][_node].interestDue += _fromInterest
  log TransferDebt(_node, _fromPool, _toPool, _fromAvailable, _fromInterest, _fromAllowance)

@internal
def _claimMerkleRewards(
      _node: address,
      _rewardIndex: DynArray[uint256, MAX_CLAIM_INTERVALS],
      _amountRPL: DynArray[uint256, MAX_CLAIM_INTERVALS],
      _amountETH: DynArray[uint256, MAX_CLAIM_INTERVALS],
      _merkleProof: DynArray[DynArray[bytes32, MAX_PROOF_LENGTH], MAX_CLAIM_INTERVALS],
      _stakeAmount: uint256
    ) -> (uint256, uint256):
  i: uint256 = 0
  maxUnclaimedIndex: uint256 = 0
  totalRPL: uint256 = self.borrowers[_node].RPL
  totalETH: uint256 = self.borrowers[_node].ETH
  for index: uint256 in _rewardIndex:
    self.intervals[_node][index] = True
    if index == self.borrowers[_node].index:
      self.borrowers[_node].index = index + 1
    self.borrowers[_node].RPL += _amountRPL[i]
    self.borrowers[_node].ETH += _amountETH[i]
    maxUnclaimedIndex = max(index + 1, maxUnclaimedIndex)
    i += 1
  totalRPL = self.borrowers[_node].RPL - totalRPL
  totalETH = self.borrowers[_node].ETH - totalETH
  self.borrowers[_node].RPL -= _stakeAmount
  distributor: RocketMerkleDistributorInterface = self._getMerkleDistributor()
  self.allowPaymentsFrom = distributor.address
  extcall distributor.claimAndStake(_node, _rewardIndex, _amountRPL, _amountETH, _merkleProof, _stakeAmount)
  self.allowPaymentsFrom = empty(address)
  self._updateIndex(_node, maxUnclaimedIndex)
  return totalRPL, totalETH

@external
def claimMerkleRewards(
      _node: address,
      _rewardIndex: DynArray[uint256, MAX_CLAIM_INTERVALS],
      _amountRPL: DynArray[uint256, MAX_CLAIM_INTERVALS],
      _amountETH: DynArray[uint256, MAX_CLAIM_INTERVALS],
      _merkleProof: DynArray[DynArray[bytes32, MAX_PROOF_LENGTH], MAX_CLAIM_INTERVALS],
      _stakeAmount: uint256
    ):
  self._checkFromBorrower(_node)
  totalRPL: uint256 = 0
  totalETH: uint256 = 0
  totalRPL, totalETH = self._claimMerkleRewards(_node, _rewardIndex, _amountRPL, _amountETH, _merkleProof, _stakeAmount)
  log ClaimRewards(_node, totalRPL, totalETH, _stakeAmount, self.borrowers[_node].RPL, self.borrowers[_node].ETH, self.borrowers[_node].index)

@internal
def _distribute(_node: address) -> uint256:
  distributor: RocketNodeDistributorInterface = self._getNodeDistributor(_node)
  nodeShare: uint256 = staticcall distributor.getNodeShare()
  self.borrowers[_node].ETH += nodeShare
  amount: uint256 = self.balance
  self.allowPaymentsFrom = distributor.address
  extcall distributor.distribute()
  self.allowPaymentsFrom = empty(address)
  assert amount + nodeShare == self.balance, "bal"
  return nodeShare

@external
def distribute(_node: address):
  self._checkFromBorrower(_node)
  log Distribute(_node, self._distribute(_node))

@internal
def _distributeMinipools(_minipools: DynArray[address, MAX_NODE_MINIPOOLS], _rewardsOnly: bool) -> uint256:
  balance: uint256 = self.balance
  for minipool: address in _minipools:
    self.allowPaymentsFrom = minipool
    extcall MinipoolInterface(minipool).distributeBalance(_rewardsOnly)
  self.allowPaymentsFrom = empty(address)
  return self.balance - balance

@internal
def _refundMinipools(_minipools: DynArray[address, MAX_NODE_MINIPOOLS]) -> uint256:
  balance: uint256 = self.balance
  for minipool: address in _minipools:
    self.allowPaymentsFrom = minipool
    extcall MinipoolInterface(minipool).refund()
  self.allowPaymentsFrom = empty(address)
  return self.balance - balance

@external
def distributeMinipools(_node: address, _minipools: DynArray[address, MAX_NODE_MINIPOOLS], _rewardsOnly: bool):
  if not _rewardsOnly:
    self._checkFromBorrower(_node)
  distributed: uint256 = self._distributeMinipools(_minipools, _rewardsOnly)
  self.borrowers[_node].ETH += distributed
  log DistributeMinipools(_node, distributed, self.borrowers[_node].ETH)

@external
def refundMinipools(_node: address, _minipools: DynArray[address, MAX_NODE_MINIPOOLS]):
  self._checkFromBorrower(_node)
  refunded: uint256 = self._refundMinipools(_minipools)
  self.borrowers[_node].ETH += refunded
  log RefundMinipools(_node, refunded, self.borrowers[_node].ETH)

@external
def withdraw(_node: address, _amountRPL: uint256, _amountETH: uint256):
  self._checkFromBorrower(_node)
  if 0 < _amountRPL:
    self.borrowers[_node].RPL -= _amountRPL
    assert extcall RPL.transfer(msg.sender, _amountRPL), "t"
  assert self._debt(_node) <= self.borrowers[_node].RPL, "debt"
  if 0 < _amountETH:
    self.borrowers[_node].ETH -= _amountETH
    self._checkBorrowLimit2(_node)
    send(msg.sender, _amountETH, gas=msg.gas)
  log Withdraw(_node, _amountRPL, _amountETH, self.borrowers[_node].RPL, self.borrowers[_node].ETH)

@external
def depositETH(_node: address, _amount: uint256):
  self._checkFromBorrower(_node)
  self.borrowers[_node].ETH -= _amount
  extcall self._getRocketNodeDeposit().depositEthFor(_node, value=_amount)
  log DepositETH(_node, _amount, self.borrowers[_node].ETH)
