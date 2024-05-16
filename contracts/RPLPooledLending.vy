#pragma version ^0.3.0

interface RPLInterface:
  def transfer(_to: address, _value: uint256) -> bool: nonpayable
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

interface RocketRewardsPoolInterface:
  def getRewardIndex() -> uint256: view
rocketRewardsPoolKey: constant(bytes32) = keccak256("contract.addressrocketRewardsPool")

MAX_INTERVALS: constant(uint256) = 128
MAX_PROOF_LENGTH: constant(uint256) = 32

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
totalBorrowedFromPool: public(HashMap[bytes32, uint256])
totalBorrowedByNode: public(HashMap[address, uint256])

# nodeAddress: the node's next withdrawal address (using this contract as the first withdrawal address)
borrowerAddress: public(HashMap[address, address])

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
  assert self.totalBorrowedFromPool[_poolId] == 0, "debt"
  assert RPL.transfer(msg.sender, self.pools[_poolId].supplied), "t"
  self.pools[_poolId].supplied = 0

# lender can withdraw supplied RPL that has not been borrowed, possibly before the end time
@external
def withdrawExcess(_poolId: bytes32, _amount: uint256):
  assert msg.sender == self.pools[_poolId].lender, "auth"
  assert _amount <= self.pools[_poolId].supplied - self.totalBorrowedFromPool[_poolId], "bal"
  assert RPL.transfer(msg.sender, _amount), "t"
  self.pools[_poolId].supplied -= _amount

# TODO: add optional pathways for claiming funds via withdrawal address:
# TODO: - claim merkle rewards
# TODO: - distribute fee distributor balance
# TODO: - distribute minipool balances
# TODO: function to indicate that merkle rewards have been claimed, if not claimed via this contract

@internal
def _getRocketNodeStaking() -> RocketNodeStakingInterface:
  return RocketNodeStakingInterface(
    rocketStorage.getAddress(rocketNodeStakingKey)
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
# reverts unless the node has set this contract as its pending withdrawal address
@external
def confirmWithdrawalAddress(_node: address):
  self.borrowerAddress[_node] = rocketStorage.getNodeWithdrawalAddress(_node)
  rocketStorage.confirmWithdrawalAddress(_node)
  self.borrowerRPL[_node] = self._getRocketNodeStaking().getNodeRPLStake(_node)
  self.accountingInterval[_node] = self._getRewardsPool().getRewardIndex()

# a borrower can change their withdrawal address for this contract
# TODO: do we want pending and force logic for this?
@external
def changeBorrowerAddress(_node: address, _newAddress: address):
  assert msg.sender == self.borrowerAddress[_node], "auth"
  self.borrowerAddress[_node] = _newAddress

# lender can claim any unclaimed rewards that have arrived in this contract
# (which is the withdrawal address for borrowing nodes)
@external
def claimLenderRewards(_poolId: bytes32):
  assert msg.sender == self.pools[_poolId].lender, "auth"
  if 0 < self.pools[_poolId].unclaimedRPL:
    assert RPL.transfer(msg.sender, self.pools[_poolId].unclaimedRPL), "t"
    self.pools[_poolId].unclaimedRPL = 0
  if 0 < self.pools[_poolId].unclaimedETH:
    send(msg.sender, self.pools[_poolId].unclaimedETH, gas=msg.gas)
    self.pools[_poolId].unclaimedETH = 0

@external
def borrow(_poolId: bytes32, _amount: uint256, _node: address):
  assert _amount + self.totalBorrowedFromPool[_poolId] <= self.pools[_poolId].supplied, "bal"
  assert rocketStorage.getNodeWithdrawalAddress(_node) == self, "wa"
  # TODO: assert RPL withdrawal address for the node is not set
  rocketNodeStaking: RocketNodeStakingInterface = self._getRocketNodeStaking()
  rocketNodeStaking.stakeRPLFor(_node, _amount)
  self.borrowed[_poolId][_node] += _amount
  self.totalBorrowedFromPool[_poolId] += _amount
  self.totalBorrowedByNode[_node] += _amount

# ETH that goes to the lender is based on the pool fee
# RPL that goes to the lender is proportional to the amount the node borrowed vs its total RPL stake

@external
def repay(_poolId: bytes32, _node: address, _amount: uint256, _amountSupplied: uint256):
  assert _amount == 0 or msg.sender == self.borrowerAddress[_node], "auth"
  total: uint256 = _amount + _amountSupplied
  assert total <= self.totalBorrowedByNode[_node], "bal"
  # TODO: update unclaimedRPL[_node] with any RPL that has been received by this contract
  # we have this information:
  #  - borrowerRPL:         what the node's RPL stake was before we became the withdrawal address (and has not yet been returned)
  #  - totalBorrowedByNode: what we have lent out to be staked and haven't received back yet
  #  - currentRPL:          what the node's current RPL stake is
  # from which we can calculate:
  # if currentRPL < borrowerRPL:
  #   borrowerRPL - currentRPL is with us and needs to be returned to the borrower
  #   also totalBorrowedByNode had better be 0 in this case... else there was a slashing maybe? anyway if it's not zero we should repay ourselves first somehow?
  # elif currentRPL - borrowerRPL < totalBorrowedByNode:
  #   totalBorrowedByNode - (currentRPL - borrowerRPL) is with us and needs to be used to repay the loan
  # else:
  #   the full stake (borrowerRPL + totalBorrowedByNode) is still staked, and possibly more is staked too
  #   update borrowerRPL to include any extra staked? but what if it was rewards that was staked to produce the excess?
  #   I guess we need to account for our rewards separately and first, to get the proportions right
  #   perhaps we should store the latest accounted reward interval index (start
  #   with current index when we become withdrawal address), and require this
  #   to be up to date
  assert _amount <= self.unclaimedRPL[_node], "bal"
  if 0 < _amountSupplied:
    assert RPL.transferFrom(msg.sender, self, _amountSupplied), "tf"
  self.unclaimedRPL[_node] -= _amount
  self.totalBorrowedByNode[_node] -= total
  self.totalBorrowedFromPool[_poolId] -= total

@external
def claimBorrowerRewards(_node: address):
  assert msg.sender == self.borrowerAddress[_node], "auth"
  if 0 < self.unclaimedRPL[_node]:
    assert RPL.transfer(msg.sender, self.unclaimedRPL[_node]), "t"
    self.unclaimedRPL[_node] = 0
  if 0 < self.unclaimedETH[_node]:
    send(msg.sender, self.unclaimedETH[_node], gas=msg.gas)
    self.unclaimedETH[_node] = 0

@external
def changeWithdrawalAddress(_node: address, _newAddress: address, _confirm: bool):
  assert msg.sender == _node or msg.sender == self.borrowerAddress[_node], "auth"
  assert self.totalBorrowedByNode[_node] == 0, "debt"
  rocketStorage.setWithdrawalAddress(_node, _newAddress, _confirm)
