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
  def setStakeRPLForAllowed(_nodeAddress: address, _caller: address, _allowed: bool): nonpayable
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

interface RocketMinipoolManagerInterface:
  def getNodeMinipoolAt(_nodeAddress: address, _index: uint256) -> address: view
rocketMinipoolManagerKey: constant(bytes32) = keccak256("contract.addressrocketMinipoolManager")

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

@internal
@view
def _getMinipoolManager() -> RocketMinipoolManagerInterface:
  return RocketMinipoolManagerInterface(
    staticcall rocketStorage.getAddress(rocketMinipoolManagerKey)
  )

nextLenderId: public(uint256)

lenderAddress: public(HashMap[uint256, address])
pendingLenderAddress: public(HashMap[uint256, address])

struct PoolParams:
  lender: uint256
  interestRate: uint8 # whole number percentage APR
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
  interestDue: uint256 # interest already accumulated (and not yet paid)
  accountedUntil: uint256 # start time for ongoing interest accumulation on borrowed

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

struct PoolItem:
  next: uint256
  poolId: bytes32
# the index of the start and the end of a linked list is 0 (i.e. last item's next == 0, and first item is the next of index 0)
# the element at index 0 is a sentinel: it stores the next unused item index, i.e. poolId == convert(len(nextIndex), bytes32)
debtPools: public(HashMap[address, HashMap[uint256, PoolItem]]) # linked list of pools in which a borrower has non-zero debt, sorted by end time, earliest first
untilList: public(HashMap[address, HashMap[uint256, PoolItem]]) # same linked list items as above, but sorted by accountedUntil time, earliest first

# assumes _poolId is active for _node, but checks _prev is the right item to insert it after
@internal
def _insertDebtPool(_node: address, _poolId: bytes32, _prev: uint256):
  newIndex: uint256 = convert(self.debtPools[_node][0].poolId, uint256)
  self.debtPools[_node][0].poolId = convert(newIndex + 1, bytes32)
  self.debtPools[_node][newIndex].poolId = _poolId
  assert self.params[self.debtPools[_node][_prev].poolId].endTime <= self.params[_poolId].endTime or _prev == 0, "p"
  nextIndex: uint256 = self.debtPools[_node][_prev].next
  assert self.params[_poolId].endTime <= self.params[self.debtPools[_node][nextIndex].poolId].endTime or nextIndex == 0, "n"
  self.debtPools[_node][newIndex].next = nextIndex
  self.debtPools[_node][_prev].next = newIndex

@internal
def _removeDebtPool(_node: address, _poolId: bytes32, _prev: uint256):
  index: uint256 = self.debtPools[_node][_prev].next
  assert self.debtPools[_node][index].poolId == _poolId, "i"
  nextIndex: uint256 = self.debtPools[_node][index].next
  self.debtPools[_node][_prev].next = nextIndex

@internal
def _insertUntilList(_node: address, _poolId: bytes32, _prev: uint256):
  newIndex: uint256 = convert(self.untilList[_node][0].poolId, uint256)
  self.untilList[_node][0].poolId = convert(newIndex + 1, bytes32)
  self.untilList[_node][newIndex].poolId = _poolId
  assert self.loans[self.untilList[_node][_prev].poolId][_node].accountedUntil <= self.loans[_poolId][_node].accountedUntil or _prev == 0, "p"
  nextIndex: uint256 = self.untilList[_node][_prev].next
  assert self.loans[_poolId][_node].accountedUntil <= self.loans[self.untilList[_node][nextIndex].poolId][_node].accountedUntil or nextIndex == 0, "n"
  self.untilList[_node][newIndex].next = nextIndex
  self.untilList[_node][_prev].next = newIndex

@internal
def _removeUntilList(_node: address, _poolId: bytes32, _prev: uint256):
  index: uint256 = self.untilList[_node][_prev].next
  assert self.untilList[_node][index].poolId == _poolId, "i"
  nextIndex: uint256 = self.untilList[_node][index].next
  self.untilList[_node][_prev].next = nextIndex

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

event PendingChangeLenderAddress:
  id: indexed(uint256)
  old: indexed(address)
  new: indexed(address)

event ConfirmChangeLenderAddress:
  id: indexed(uint256)
  old: indexed(address)
  new: indexed(address)
  oldPending: address

event CreatePool:
  id: indexed(bytes32)
  params: PoolParams

event SupplyPool:
  id: indexed(bytes32)
  total: indexed(uint256)

event SetAllowance:
  id: indexed(bytes32)
  old: indexed(uint256)
  new: indexed(uint256)

event ChangeAllowedToBorrow:
  id: indexed(bytes32)
  node: indexed(address)
  allowed: indexed(bool)

event WithdrawETHFromPool:
  id: indexed(bytes32)

event WithdrawRPLFromPool:
  id: indexed(bytes32)

event WithdrawInterest:
  id: indexed(bytes32)
  amount: indexed(uint256)

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

event ChargeInterest:
  id: indexed(bytes32)
  node: indexed(address)
  charged: uint256
  total: uint256
  until: uint256

@external
def registerLender() -> uint256:
  id: uint256 = self.nextLenderId
  self.lenderAddress[id] = msg.sender
  self.nextLenderId = id + 1
  log RegisterLender(id, msg.sender)
  return id

@internal
def _updateLenderAddress(_lender: uint256, _newAddress: address):
  log ConfirmChangeLenderAddress(_lender, self.lenderAddress[_lender], _newAddress, self.pendingLenderAddress[_lender])
  self.pendingLenderAddress[_lender] = empty(address)
  self.lenderAddress[_lender] = _newAddress

@external
def changeLenderAddress(_lender: uint256, _newAddress: address, _confirm: bool):
  assert msg.sender == self.lenderAddress[_lender], "auth"
  if _confirm:
    self._updateLenderAddress(_lender, _newAddress)
  else:
    log PendingChangeLenderAddress(_lender, self.pendingLenderAddress[_lender], _newAddress)
    self.pendingLenderAddress[_lender] = _newAddress

@external
def confirmChangeLenderAddress(_lender: uint256):
  assert msg.sender == self.pendingLenderAddress[_lender], "auth"
  self._updateLenderAddress(_lender, msg.sender)

@internal
def _poolId(_params: PoolParams) -> bytes32:
  return keccak256(concat(
                     convert(_params.lender, bytes32),
                     convert(_params.interestRate, bytes1),
                     convert(_params.endTime, bytes32)
                  ))

@external
def createPool(_params: PoolParams, _supply: uint256, _allowance: uint256, _borrowers: DynArray[address, MAX_ADDRESS_BATCH]) -> bytes32:
  assert msg.sender == self.lenderAddress[_params.lender], "auth"
  poolId: bytes32 = self._poolId(_params)
  self.params[poolId] = _params
  log CreatePool(poolId, _params)
  if 0 < _supply:
    assert extcall RPL.transferFrom(msg.sender, self, _supply), "tf"
    self.pools[poolId].available += _supply
    log SupplyPool(poolId, self.pools[poolId].available)
  if 0 < _allowance:
    self.pools[poolId].allowance = _allowance
    log SetAllowance(poolId, 0, _allowance)
  for node: address in _borrowers:
    self.allowedToBorrow[poolId][node] = True
    log ChangeAllowedToBorrow(poolId, node, True)
  return poolId

@internal
@view
def _lenderAddress(_poolId: bytes32) -> address:
  return self.lenderAddress[self.params[_poolId].lender]

@internal
def _checkFromLender(_poolId: bytes32):
  assert msg.sender == self._lenderAddress(_poolId), "auth"

@external
def changePoolRPL(_poolId: bytes32,
                  _withdrawInterest: uint256,
                  _targetSupply: uint256):
  requireLender: bool = False
  if 0 < _withdrawInterest:
    requireLender = True
    self.pools[_poolId].interestPaid -= _withdrawInterest
    self.pools[_poolId].available += _withdrawInterest
    log WithdrawInterest(_poolId, _withdrawInterest)
  currentSupply: uint256 = self.pools[_poolId].available
  if _targetSupply < currentSupply:
    requireLender = True
    assert extcall RPL.transfer(msg.sender, currentSupply - _targetSupply), "t"
    log WithdrawRPLFromPool(_poolId)
  elif currentSupply < _targetSupply:
    assert extcall RPL.transferFrom(msg.sender, self, _targetSupply - currentSupply), "tf"
    log SupplyPool(_poolId, _targetSupply)
  if requireLender:
    self._checkFromLender(_poolId)
  self.pools[_poolId].available = _targetSupply

@external
def withdrawEtherFromPool(_poolId: bytes32, _amount: uint256):
  self._checkFromLender(_poolId)
  self.pools[_poolId].reclaimed -= _amount
  log WithdrawETHFromPool(_poolId)
  send(msg.sender, _amount, gas=msg.gas)

addressMask: constant(uint256) = ~0 >> (32 - 20)
allowedBit: constant(uint256) = 1 << 20

@external
def changeAllowedToBorrow(_poolId: bytes32, _borrowers: DynArray[uint256, MAX_ADDRESS_BATCH]):
  self._checkFromLender(_poolId)
  for arg: uint256 in _borrowers:
    node: address = convert(arg & addressMask, address)
    allowed: bool = convert(arg & allowedBit, bool)
    self.allowedToBorrow[_poolId][node] = allowed
    log ChangeAllowedToBorrow(_poolId, node, allowed)

@external
def setAllowance(_poolId: bytes32, _allowance: uint256):
  self._checkFromLender(_poolId)
  log SetAllowance(_poolId, self.pools[_poolId].allowance, _allowance)
  self.pools[_poolId].allowance = _allowance

@external
def updateInterestDue(_poolId: bytes32, _node: address):
  self._chargeInterest(_poolId, _node)

@internal
def _chargeAndCheckEndedOwing(_poolId: bytes32, _node: address):
  endTime: uint256 = self.params[_poolId].endTime
  assert endTime < block.timestamp, "term"
  self._chargeInterest(_poolId, _node)
  assert 0 < self.loans[_poolId][_node].borrowed or 0 < self.loans[_poolId][_node].interestDue, "paid"

@external
def forceRepayRPL(_poolId: bytes32, _node: address, _unstakeAmount: uint256):
  self._chargeAndCheckEndedOwing(_poolId, _node)
  if 0 < _unstakeAmount:
    extcall self._getRocketNodeStaking().withdrawRPL(_node, _unstakeAmount)
    self.borrowers[_node].RPL += _unstakeAmount
  available: uint256 = self.borrowers[_node].RPL
  if 0 < _unstakeAmount:
    assert available <= self.loans[_poolId][_node].interestDue + self.loans[_poolId][_node].borrowed, "wd"
  available = self._payDebt(_poolId, _node, available)
  assert available < self.borrowers[_node].RPL, "none"
  self.borrowers[_node].RPL = available
  log ForceRepayRPL(_poolId, _node, _unstakeAmount, available, self.borrowers[_node].borrowed, self.borrowers[_node].interestDue)

@external
def forceRepayETH(_poolId: bytes32, _node: address):
  self._checkFromLender(_poolId)
  self._chargeAndCheckEndedOwing(_poolId, _node)
  ethPerRpl: uint256 = staticcall self._getRocketNetworkPrices().getRPLPrice()
  startAmountETH: uint256 = self.borrowers[_node].ETH
  endAmountETH: uint256 = (self._payDebt(_poolId, _node, (startAmountETH * oneEther) // ethPerRpl) * ethPerRpl) // oneEther
  reclaimedETH: uint256 = startAmountETH - endAmountETH
  assert 0 < reclaimedETH, "none"
  self.borrowers[_node].ETH = endAmountETH
  self.pools[_poolId].reclaimed += reclaimedETH
  log ForceRepayETH(_poolId, _node, reclaimedETH, self.borrowers[_node].ETH, self.borrowers[_node].borrowed, self.borrowers[_node].interestDue)

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
  self._chargeAndCheckEndedOwing(_poolId, _node)
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
                          _minipools: DynArray[MinipoolArgument, MAX_NODE_MINIPOOLS]):
  self._checkFromLender(_poolId)
  self._chargeAndCheckEndedOwing(_poolId, _node)
  total: uint256 = self._claim(_node, _distribute, _minipools)
  assert 0 < total, "none"
  ethPerRpl: uint256 = staticcall self._getRocketNetworkPrices().getRPLPrice()
  startAmountETH: uint256 = self.borrowers[_node].ETH
  endAmountETH: uint256 = (self._payDebt(_poolId, _node, (startAmountETH * oneEther) // ethPerRpl) * ethPerRpl) // oneEther

  reclaimedETH: uint256 = startAmountETH - endAmountETH
  assert 0 < reclaimedETH, "none"
  self.borrowers[_node].ETH = endAmountETH
  self.pools[_poolId].reclaimed += reclaimedETH
  log ForceDistributeRefund(_poolId, _node, total, reclaimedETH, self.borrowers[_node].ETH,
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

event UnstakeRPL:
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

event DistributeRefund:
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
  currentWithdrawalAddress: address = staticcall rocketStorage.getNodeWithdrawalAddress(_node)
  if currentWithdrawalAddress == self:
    assert msg.sender == _node, "auth"
    self.borrowers[_node].address = _node
  else:
    self.borrowers[_node].address = currentWithdrawalAddress
    extcall rocketStorage.confirmWithdrawalAddress(_node)
  extcall self._getRocketNodeManager().setRPLWithdrawalAddress(_node, self, True)
  rocketNodeStaking: RocketNodeStakingInterface = self._getRocketNodeStaking()
  if staticcall rocketNodeStaking.getRPLLockingAllowed(_node):
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
  self.borrowers[_node].pending = empty(address)
  log LeaveProtocol(_node)

@internal
def _stakeRPLFor(_node: address, _amount: uint256):
  rocketNodeStaking: RocketNodeStakingInterface = self._getRocketNodeStaking()
  assert extcall RPL.approve(rocketNodeStaking.address, _amount), "a"
  extcall rocketNodeStaking.stakeRPLFor(_node, _amount)

@external
def stakeRPLFor(_node: address, _amount: uint256):
  self._checkFromBorrower(_node)
  assert extcall RPL.transferFrom(msg.sender, self, _amount), "tf"
  self._stakeRPLFor(_node, _amount)

@external
def setStakeRPLForAllowed(_node: address, _caller: address, _allowed: bool):
  self._checkFromBorrower(_node)
  extcall self._getRocketNodeStaking().setStakeRPLForAllowed(_node, _caller, _allowed)

@external
def unstakeRPL(_node: address, _amount: uint256):
  self._checkFromBorrower(_node)
  extcall self._getRocketNodeStaking().withdrawRPL(_node, _amount)
  self.borrowers[_node].RPL += _amount
  log UnstakeRPL(_node, _amount, self.borrowers[_node].RPL)

@internal
@view
def _outstandingInterest(_borrowed: uint256, _rate: uint8, _startTime: uint256, _endTime: uint256) -> uint256:
  # _rate is percentage RPL per RPL per Year
  return _borrowed * convert(_rate, uint256) * (_endTime - _startTime) // 100 // SECONDS_PER_YEAR

@internal
def _chargeInterest(_poolId: bytes32, _node: address):
  borrowed: uint256 = self.loans[_poolId][_node].borrowed
  startTime: uint256 = self.loans[_poolId][_node].accountedUntil
  endTime: uint256 = self.params[_poolId].endTime
  rate: uint8 = self.params[_poolId].interestRate
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
  self.loans[_poolId][_node].accountedUntil = block.timestamp
  log ChargeInterest(_poolId, _node, amount, self.borrowers[_node].interestDue, block.timestamp)

@internal
def _repayInterest(_poolId: bytes32, _node: address, _amount: uint256) -> uint256:
  if 0 < _amount:
    self.loans[_poolId][_node].interestDue -= _amount
    self.borrowers[_node].interestDue -= _amount
    self.pools[_poolId].interestPaid += _amount
  return _amount

@internal
def _lend(_poolId: bytes32, _node: address, _amount: uint256, _index: uint256):
  if 0 < _amount:
    assert (self.allowedToBorrow[_poolId][empty(address)] or
            self.allowedToBorrow[_poolId][_node]), "r"
    if (self.loans[_poolId][_node].borrowed == 0 and
        self.loans[_poolId][_node].interestDue == 0):
      self._insertDebtPool(_node, _poolId, _index)
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
def _availableRPL(_node: address) -> uint256:
  return (staticcall self._getRocketNodeStaking().getNodeRPLStake(_node)
          + self.borrowers[_node].RPL)

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
def borrow(_poolId: bytes32, _node: address, _amount: uint256, _index: uint256):
  self._checkFromBorrower(_node)
  assert block.timestamp < self.params[_poolId].endTime, "end"
  self._stakeRPLFor(_node, _amount)
  self._chargeInterest(_poolId, _node)
  self._lend(_poolId, _node, _amount, _index)
  self._checkBorrowLimit(_node)
  log Borrow(_poolId, _node, _amount,
             self.loans[_poolId][_node].borrowed,
             self.loans[_poolId][_node].interestDue)

@external
def repay(_poolId: bytes32, _node: address, _unstakeAmount: uint256, _repayAmount: uint256):
  isBorrower: bool = msg.sender == self.borrowers[_node].address
  assert _unstakeAmount == 0 or isBorrower, "auth"
  self._chargeInterest(_poolId, _node)
  rocketNodeStaking: RocketNodeStakingInterface = self._getRocketNodeStaking()
  if 0 < _unstakeAmount:
    extcall rocketNodeStaking.withdrawRPL(_node, _unstakeAmount)
    self.borrowers[_node].RPL += _unstakeAmount
  target: uint256 = _repayAmount
  if target == 0:
    target = self.loans[_poolId][_node].interestDue + self.loans[_poolId][_node].borrowed
  obtained: uint256 = 0
  if isBorrower:
    obtained = min(target, self.borrowers[_node].RPL)
    self.borrowers[_node].RPL -= obtained
  if obtained < target:
    assert extcall RPL.transferFrom(msg.sender, self, target - obtained), "tf"
    obtained = target
  assert self._payDebt(_poolId, _node, obtained) == 0, "over"
  log Repay(_poolId, _node, obtained,
            self.loans[_poolId][_node].borrowed,
            self.loans[_poolId][_node].interestDue)

@external
def transferDebt(_node: address, _fromPool: bytes32, _toPool: bytes32, _index: uint256,
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
    self._lend(_toPool, _node, _fromAvailable, _index)
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

flag MinipoolAction:
  Distribute
  NotRewardsOnly
  Refund

struct MinipoolArgument:
  index: uint256
  action: MinipoolAction

@internal
def _claim(
  _node: address,
  _dist: bool,
  _args: DynArray[MinipoolArgument, MAX_NODE_MINIPOOLS],
) -> uint256:
  total: uint256 = 0
  if _dist:
    distributor: RocketNodeDistributorInterface = self._getNodeDistributor(_node)
    nodeShare: uint256 = staticcall distributor.getNodeShare()
    self.borrowers[_node].ETH += nodeShare
    amount: uint256 = self.balance
    self.allowPaymentsFrom = distributor.address
    extcall distributor.distribute()
    self.allowPaymentsFrom = empty(address)
    assert amount + nodeShare == self.balance, "bal"
    total += nodeShare
  if len(_args) == 0:
    return total
  minipool: address = empty(address)
  manager: RocketMinipoolManagerInterface = self._getMinipoolManager()
  balance: uint256 = self.balance
  for arg: MinipoolArgument in _args:
    minipool = staticcall manager.getNodeMinipoolAt(_node, arg.index)
    self.allowPaymentsFrom = minipool
    if MinipoolAction.Refund in arg.action:
      extcall MinipoolInterface(minipool).refund()
    if MinipoolAction.Distribute in arg.action:
      extcall MinipoolInterface(minipool).distributeBalance(MinipoolAction.NotRewardsOnly not in arg.action)
  self.allowPaymentsFrom = empty(address)
  total += self.balance - balance
  return total

@external
def distributeRefund(_node: address,
                     _distribute: bool,
                     _minipools: DynArray[MinipoolArgument, MAX_NODE_MINIPOOLS]):
  needCheckFromBorrower: bool = False
  for arg: MinipoolArgument in _minipools:
    if MinipoolAction.NotRewardsOnly in arg.action or MinipoolAction.Refund in arg.action:
      needCheckFromBorrower = True
      break
  if needCheckFromBorrower:
    self._checkFromBorrower(_node)
  total: uint256 = self._claim(_node, _distribute, _minipools)
  self.borrowers[_node].ETH += total
  log DistributeRefund(_node, total, self.borrowers[_node].ETH)

@external
def withdraw(_node: address, _amountRPL: uint256, _amountETH: uint256):
  self._checkFromBorrower(_node)
  if 0 < _amountRPL:
    self.borrowers[_node].RPL -= _amountRPL
    assert extcall RPL.transfer(msg.sender, _amountRPL), "t"
  assert self._debt(_node) <= self._availableRPL(_node), "debt"
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
