import time
import datetime
import pytest
from eth_utils import keccak
from ape import reverts

# Setup

## Constants

rocketStorageAddresses = dict(
        mainnet='0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46',
        holesky='0x594Fb75D3dc2DFa0150Ad03F99F97817747dd4E1')

SECONDS_PER_YEAR = 365 * 24 * 60 * 60

nullAddress = '0x0000000000000000000000000000000000000000'

stakingStatus = 2

Distribute = 0
NotRewardsOnly = 1
Refund = 2

allowedBit = 1 << (20 * 8)

def mark_allowed(nodes):
    return [int(node, 16) | allowedBit for node in nodes]

def mark_not_allowed(nodes):
    return [int(node, 16) for node in nodes]

def time_from_now(**kwargs):
    return round(time.time() + datetime.timedelta(**kwargs).total_seconds())

## Rocket Pool contracts

@pytest.fixture()
def rocketStorage(chain, Contract):
    return Contract(rocketStorageAddresses[chain.provider.network.name.removesuffix('-fork')])

@pytest.fixture()
def minipoolABI(rocketStorage, Contract):
    delegate = Contract(rocketStorage.getAddress(keccak('contract.addressrocketMinipoolDelegate'.encode())))
    return list(delegate.identifier_lookup.values())

@pytest.fixture()
def RPLToken(rocketStorage, Contract):
    return Contract(rocketStorage.getAddress(keccak('contract.addressrocketTokenRPL'.encode())))

@pytest.fixture()
def rocketVaultImpersonated(rocketStorage, accounts):
    return accounts[rocketStorage.getAddress(keccak('contract.addressrocketVault'.encode()))]

@pytest.fixture()
def rocketNodeManager(rocketStorage, Contract):
    return Contract(rocketStorage.getAddress(keccak('contract.addressrocketNodeManager'.encode())))

@pytest.fixture()
def rocketMinipoolManager(rocketStorage, Contract):
    return Contract(rocketStorage.getAddress(keccak('contract.addressrocketMinipoolManager'.encode())))

@pytest.fixture()
def rocketNodeStaking(rocketStorage, Contract):
    return Contract(rocketStorage.getAddress(keccak('contract.addressrocketNodeStaking'.encode())))

@pytest.fixture()
def rocketNodeDeposit(rocketStorage, Contract):
    return Contract(rocketStorage.getAddress(keccak('contract.addressrocketNodeDeposit'.encode())))

@pytest.fixture()
def rocketRewardsPool(rocketStorage, Contract):
    return Contract(rocketStorage.getAddress(keccak('contract.addressrocketRewardsPool'.encode())))

@pytest.fixture()
def rocketMerkleDistributor(rocketStorage, Contract):
    return Contract(rocketStorage.getAddress(keccak('contract.addressrocketMerkleDistributorMainnet'.encode())))

@pytest.fixture()
def rocketNetworkPrices(rocketStorage, Contract):
    return Contract(rocketStorage.getAddress(keccak('contract.addressrocketNetworkPrices'.encode())))

def grab_RPL(who, amount, RPLToken, rocketVaultImpersonated, approveFor):
    RPLToken.transfer(who, amount, sender=rocketVaultImpersonated)
    if approveFor:
        RPLToken.approve(approveFor, amount, sender=who)

def get_debt(_rocketlend, _node):
    return _rocketlend.borrowers(_node).borrowed + _rocketlend.borrowers(_node).interestDue

## Accounts

@pytest.fixture()
def deployer(accounts):
    return accounts[5]

@pytest.fixture()
def admin(accounts):
    return accounts[4]

@pytest.fixture()
def other(accounts):
    return accounts[3]

@pytest.fixture()
def lender1(accounts):
    return accounts[1]

@pytest.fixture()
def lender2(accounts):
    return accounts[2]

@pytest.fixture()
def node1(rocketNodeManager, rocketStorage, accounts):
    nodeAddress = rocketNodeManager.getNodeAt(4)
    node = accounts[nodeAddress]
    if node.balance < 10 ** 18:
      accounts[3].transfer(nodeAddress, '1 ETH')
    current_wa = rocketStorage.getNodeWithdrawalAddress(node)
    if current_wa == node:
      rocketStorage.setWithdrawalAddress(node, accounts[0], True, sender=node)
    elif accounts[current_wa].balance < 10 ** 18:
      accounts[0].transfer(current_wa, '1 ETH')
    return node

@pytest.fixture()
def node2(rocketNodeManager, accounts):
    nodeAddress = rocketNodeManager.getNodeAt(69)
    return accounts[nodeAddress]

@pytest.fixture()
def node3(rocketNodeManager, accounts):
    nodeAddress = rocketNodeManager.getNodeAt(420)
    node = accounts[nodeAddress]
    if node.balance < 10 ** 18:
      accounts[3].transfer(nodeAddress, '1 ETH')
    return node

@pytest.fixture()
def nodeWithMPs(rocketNodeManager, rocketMinipoolManager, accounts):
    nodeAddress = rocketNodeManager.getNodeAt(252)
    node = accounts[nodeAddress]
    if node.balance < 10 ** 18:
      accounts[3].transfer(nodeAddress, '1 ETH')
    assert rocketMinipoolManager.getNodeActiveMinipoolCount(node) > 1
    return node

## Deployment and basic tests post-deployment

@pytest.fixture()
def rocketlend(project, rocketStorage, deployer):
    return deployer.deploy(project.rocketlend, rocketStorage)

def test_send_eth_other(rocketlend, other):
    with reverts('revert: a'):
        other.transfer(rocketlend, 20)

def test_set_name_other(rocketlend, other, Contract):
    receipt = rocketlend.setName(sender=other)
    ensRegistry = Contract('0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e')
    addrReverseNode = '0x91d1777781884d03a6757a803996e38de2a42967fb37eeaca72729271025a9e2'
    rocketlendNode = '0x07f70f0e37149c5ddb4e9d570b149208628f3fdd1a4f624d8f1be396063dd595'
    resolver = Contract(ensRegistry.resolver(rocketlendNode))
    reverseRegistry = Contract(ensRegistry.owner(addrReverseNode))
    rev_logs = reverseRegistry.ReverseClaimed.from_receipt(receipt)
    logs = resolver.NameChanged.from_receipt(receipt)
    assert len(rev_logs) == 1
    assert len(logs) == 1
    assert rev_logs[0].addr == rocketlend
    assert rev_logs[0].node == logs[0].node
    assert logs[0].name == 'rocketlend.eth'

# Fixture situations

## Lender registration

@pytest.fixture()
def rocketlendReg1(rocketlend, lender1):
    receipt = rocketlend.registerLender(sender=lender1)
    log = rocketlend.RegisterLender.from_receipt(receipt)[0]
    return dict(rocketlend=rocketlend,
                lenderId=receipt.return_value,
                lenderAddress=lender1.address)

@pytest.fixture()
def rocketlendReg2(rocketlendReg1, lender2):
    rocketlendReg1["rocketlend"].registerLender(sender=lender2)
    return rocketlendReg1["rocketlend"]

@pytest.fixture()
def rocketlendf(rocketlendReg2, node3):
    rocketlendReg2.registerLender(sender=node3)
    return rocketlendReg2

## Pool creation

@pytest.fixture()
def rocketlendp(rocketlendf, RPLToken, rocketVaultImpersonated, lender2):
    amount = 200 * 10 ** RPLToken.decimals()
    grab_RPL(lender2, amount, RPLToken, rocketVaultImpersonated, rocketlendf)
    endTime=time_from_now(weeks=2)
    params = dict(lender=1, interestRate=10, endTime=endTime)
    receipt = rocketlendf.createPool(params, amount, 0, [0], sender=lender2)
    poolId = receipt.return_value
    return dict(receipt=receipt, lenderId=1, lender=lender2, rocketlend=rocketlendf, poolId=poolId, endTime=endTime, amount=amount)

## Borrower joining

@pytest.fixture()
def borrower1(rocketlendp, node1, rocketStorage, accounts):
    current_wa = accounts[rocketStorage.getNodeWithdrawalAddress(node1)]
    rocketlend = rocketlendp['rocketlend']
    rocketStorage.setWithdrawalAddress(node1, rocketlend, False, sender=current_wa)
    rocketlend.joinAsBorrower(node1, sender=current_wa)
    return dict(node=node1, borrower=current_wa, rocketlend=rocketlend)

@pytest.fixture()
def nodeWithMPsJoined(rocketlend, rocketStorage, other, nodeWithMPs, accounts):
    current_wa = accounts[rocketStorage.getNodeWithdrawalAddress(nodeWithMPs)]
    rocketStorage.setWithdrawalAddress(nodeWithMPs, rocketlend, False, sender=current_wa)
    rocketlend.joinAsBorrower(nodeWithMPs, sender=other)
    return dict(node=nodeWithMPs, borrower=current_wa)

## Borrowing

@pytest.fixture()
def borrower1b(rocketlendp, RPLToken, rocketNodeDeposit, borrower1, other):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    node = borrower1['node']
    borrower = borrower1['borrower']
    amount = 50 * 10 ** RPLToken.decimals()
    rocketNodeDeposit.depositEthFor(node, value='8 ether', sender=other)
    receipt = rocketlend.borrow(poolId, node, 0, amount, sender=borrower)
    return dict(borrower1, poolId=poolId, lender=rocketlendp['lender'], amount=amount, receipt=receipt)

## Repayment

@pytest.fixture()
def partialRepayment(borrower1b, other, RPLToken, rocketVaultImpersonated):
    rocketlend = borrower1b['rocketlend']
    poolId = borrower1b['poolId']
    amountBorrowed = borrower1b['amount']
    node = borrower1b['node']
    amount = amountBorrowed // 2
    grab_RPL(other, amount, RPLToken, rocketVaultImpersonated, rocketlend)
    receipt = rocketlend.repay(poolId, node, 0, 0, amount, sender=other)
    return dict(receipt=receipt, node=node, amount=amount, rocketlend=rocketlend, poolId=poolId, lender=borrower1b['lender'])

## Rewards

@pytest.fixture()
def distributedRewards(rocketlend, nodeWithMPsJoined, rocketMinipoolManager, Contract, minipoolABI, accounts):
    node = nodeWithMPsJoined['node']
    minipool = None
    index = 0
    while minipool == None:
        minipool = Contract(rocketMinipoolManager.getNodeMinipoolAt(node, index), abi=minipoolABI)
        if (minipool.getStatus() != stakingStatus):
            minipool = None
            index += 1
    accounts[1].transfer(minipool, 3 * 10 ** 18)
    receipt = rocketlend.distributeRefund(node, False, [[index, 1 << Distribute]], sender=accounts[1])
    return dict(rocketlend=rocketlend, node=node, minipool=minipool, receipt=receipt)

# Per-function tests

## Views

### params

def test_next_lender_id_incremented(rocketlendReg1):
    rocketlend = rocketlendReg1['rocketlend']
    prev_id = rocketlendReg1['lenderId']
    assert rocketlend.params(0).lender == prev_id + 1

def test_lender_set(rocketlendp):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    lender = rocketlendp['lenderId']
    assert rocketlend.params(poolId).lender == lender

def test_end_time_set(rocketlendp):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    endTime = rocketlend.params(poolId).endTime
    assert endTime == rocketlendp['endTime']
    assert 0 < endTime
    assert (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=13) <
            datetime.datetime.fromtimestamp(endTime, datetime.timezone.utc))

### pools

def test_supply_set(rocketlendp):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    receipt = rocketlendp['receipt']
    log = rocketlend.SupplyPool.from_receipt(receipt)[0]
    assert rocketlend.pools(poolId).available == log.total

def test_allowance_set(rocketlendp):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    assert rocketlend.pools(poolId).allowance == 0

### loans

def test_view_loan(borrower1b):
    rocketlend = borrower1b['rocketlend']
    poolId = borrower1b['poolId']
    node = borrower1b['node']
    borrower = borrower1b['borrower']
    assert rocketlend.loans(poolId, node).borrowed == borrower1b['amount']
    assert rocketlend.loans(poolId, borrower).borrowed == 0

### allowedToBorrow

def test_allowed_to_borrow_set(rocketlendp):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    lender = rocketlendp['lender']
    assert rocketlend.allowedToBorrow(poolId, nullAddress)
    assert not rocketlend.allowedToBorrow(poolId, lender)

### borrowers

def test_view_borrowed(rocketlendp, borrower1b):
    rocketlend = rocketlendp['rocketlend']
    node = borrower1b['node']
    assert rocketlend.borrowers(node)['borrowed'] == borrower1b['amount']

### intervals

def test_intervals_set_first_10(borrower1, rocketRewardsPool, rocketMerkleDistributor):
    rocketlend = borrower1['rocketlend']
    node = borrower1['node']
    current_index = rocketRewardsPool.getRewardIndex()
    assert rocketlend.borrowers(node).index == current_index
    for i in range(max(current_index, 10)):
        rocketlend.intervals(node, i) == rocketMerkleDistributor.isClaimed(i, node)

### lenderAddress

def test_lender_address_set(rocketlendReg1):
    rocketlend = rocketlendReg1['rocketlend']
    lenderAddress = rocketlendReg1['lenderAddress']
    lenderId = rocketlendReg1['lenderId']
    assert lenderAddress == rocketlend.lenderAddress(lenderId)

### pendingLenderAddress
#### see test_change_lender_address

### rocketStorage

def test_rocketstorage_address(rocketlend, rocketStorage):
    assert rocketlend.rocketStorage() == rocketStorage.address

### RPL

def test_RPL_token_address(rocketlend, RPLToken):
    assert rocketlend.RPL() == RPLToken.address

## Lender actions

### registerLender

def test_register_lender1(rocketlend, lender1):
    nextId = rocketlend.params(0).lender
    assert nextId == 0
    receipt = rocketlend.registerLender(sender=lender1)
    assert receipt.return_value == nextId
    logs = rocketlend.RegisterLender.from_receipt(receipt)
    assert len(logs) == 1
    assert logs[0].lender == nextId

### changeLenderAddress
### confirmChangeLenderAddress

def test_change_lender_address_other(rocketlendReg1, other):
    rocketlend = rocketlendReg1["rocketlend"]
    lenderId = rocketlendReg1["lenderId"]
    lenderAddress = rocketlendReg1["lenderAddress"]
    with reverts('revert: a'):
        rocketlend.changeLenderAddress(lenderId, lenderAddress, False, sender=other)
    with reverts('revert: a'):
        rocketlend.changeLenderAddress(lenderId, other, False, sender=other)
    with reverts('revert: a'):
        rocketlend.changeLenderAddress(lenderId, lenderAddress, True, sender=other)

def test_change_lender_address(rocketlendReg1, lender1, other):
    rocketlend = rocketlendReg1["rocketlend"]
    lenderId = rocketlendReg1["lenderId"]
    lenderAddress = rocketlendReg1["lenderAddress"]
    assert lender1 == lenderAddress
    rocketlend.changeLenderAddress(lenderId, other, False, sender=lender1)
    assert rocketlend.lenderAddress(lenderId) == lender1
    assert rocketlend.pendingLenderAddress(lenderId) == other
    with reverts('revert: a'):
        rocketlend.confirmChangeLenderAddress(lenderId, sender=lender1)
    receipt = rocketlend.confirmChangeLenderAddress(lenderId, sender=other)
    assert rocketlend.lenderAddress(lenderId) == other
    assert rocketlend.pendingLenderAddress(lenderId) == nullAddress
    logs = rocketlend.ConfirmChangeLenderAddress.from_receipt(receipt)
    assert len(logs) == 1

def test_change_lender_address_force(rocketlendReg1, lender1, other):
    rocketlend = rocketlendReg1["rocketlend"]
    lenderId = rocketlendReg1["lenderId"]
    lenderAddress = rocketlendReg1["lenderAddress"]
    receipt = rocketlend.changeLenderAddress(lenderId, other, True, sender=lender1)
    assert rocketlend.lenderAddress(lenderId) == other
    assert rocketlend.pendingLenderAddress(lenderId) == nullAddress

### createPool

def test_create_pool_unregistered(rocketlend, other):
    with reverts('revert: a'):
        rocketlend.createPool(dict(lender=0, interestRate=0, endTime=0), 0, 0, [0], sender=other)

def test_create_expired_pool(rocketlendReg1, lender1):
    params = dict(lender=rocketlendReg1["lenderId"], interestRate=0, endTime=0)
    rocketlend = rocketlendReg1["rocketlend"]
    receipt = rocketlend.createPool(params, 0, 0, [0], sender=lender1)
    logs = rocketlend.CreatePool.from_receipt(receipt)
    assert len(logs) == 1
    assert logs[0].id == receipt.return_value

def test_create_pool(rocketlendf, lender2):
    params = dict(lender=1, interestRate=1, endTime=time_from_now(days=3))
    receipt = rocketlendf.createPool(params, 0, 0, [0], sender=lender2)
    logs = rocketlendf.CreatePool.from_receipt(receipt)
    assert len(logs) == 1
    assert logs[0].id == receipt.return_value

def test_create_pool_with_supply(rocketlendf, RPLToken, rocketVaultImpersonated, lender2):
    amount = 20 * 10 ** RPLToken.decimals()
    grab_RPL(lender2, amount, RPLToken, rocketVaultImpersonated, rocketlendf)
    params = dict(lender=1, interestRate=1, endTime=time_from_now(days=3))
    receipt = rocketlendf.createPool(params, amount, 0, [0], sender=lender2)
    logs = rocketlendf.CreatePool.from_receipt(receipt)
    assert len(logs) == 1
    assert logs[0].id == receipt.return_value

### setAllowance

def test_set_allowance_other(rocketlendp, other):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    with reverts('revert: a'):
        rocketlend.setAllowance(poolId, 0, sender=other)

def test_set_allowance_zero(rocketlendp):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    lender = rocketlendp['lender']
    rocketlend.setAllowance(poolId, 0, sender=lender)
    assert rocketlend.pools(poolId).allowance == 0

def test_set_allowance_nonzero(rocketlendp):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    lender = rocketlendp['lender']
    amount = 1000000
    receipt = rocketlend.setAllowance(poolId, amount, sender=lender)
    assert rocketlend.pools(poolId).allowance == amount
    logs = rocketlend.SetAllowance.from_receipt(receipt)
    assert len(logs) == 1
    assert logs[0].old == 0

### changeAllowedToBorrow

def test_change_allowed_to_borrow_other(rocketlendp, other):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    with reverts('revert: a'):
        rocketlend.changeAllowedToBorrow(poolId, [], sender=other)

def test_change_allowed_to_borrow_true(rocketlendp, node1, node2):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    lender = rocketlendp['lender']
    receipt = rocketlend.changeAllowedToBorrow(poolId, mark_not_allowed([nullAddress]) + mark_allowed([node1.address, node2.address]), sender=lender)
    assert not rocketlend.allowedToBorrow(poolId, nullAddress)
    assert rocketlend.allowedToBorrow(poolId, node1)
    assert rocketlend.allowedToBorrow(poolId, node2)
    logs = rocketlend.ChangeAllowedToBorrow.from_receipt(receipt)
    assert len(logs) == 3

def test_change_allowed_to_borrow_false_partial(rocketlendp, node1, node2):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    lender = rocketlendp['lender']
    rocketlend.changeAllowedToBorrow(poolId, mark_not_allowed([nullAddress]) + mark_allowed([node1.address, node2.address]), sender=lender)
    rocketlend.changeAllowedToBorrow(poolId, mark_not_allowed([node1.address]), sender=lender)
    assert not rocketlend.allowedToBorrow(poolId, nullAddress)
    assert not rocketlend.allowedToBorrow(poolId, node1)
    assert rocketlend.allowedToBorrow(poolId, node2)

def test_change_allowed_to_borrow_false_extra(rocketlendp, node1, node2):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    lender = rocketlendp['lender']
    rocketlend.changeAllowedToBorrow(poolId, mark_allowed([node1.address]), sender=lender)
    rocketlend.changeAllowedToBorrow(poolId, mark_not_allowed([nullAddress, node1.address, node2.address]), sender=lender)
    assert not rocketlend.allowedToBorrow(poolId, nullAddress)
    assert not rocketlend.allowedToBorrow(poolId, node1)
    rocketlend.changeAllowedToBorrow(poolId, mark_allowed([nullAddress]), sender=lender)
    assert rocketlend.allowedToBorrow(poolId, nullAddress)
    assert not rocketlend.allowedToBorrow(poolId, node1)

### changePoolRPL

def test_withdraw_other(rocketlendp, other):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    amount = rocketlendp['amount'] // 2
    with reverts('revert: a'):
        rocketlend.changePoolRPL(poolId, 0, amount, sender=other)

def test_withdraw_unborrowed(rocketlendp, RPLToken):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    lender = rocketlendp['lender']
    amount = rocketlendp['amount']
    before = RPLToken.balanceOf(lender)
    targetAmount = amount - amount // 3
    receipt = rocketlend.changePoolRPL(poolId, 0, targetAmount, sender=lender)
    after = RPLToken.balanceOf(lender)
    logs = rocketlend.WithdrawRPLFromPool.from_receipt(receipt)
    assert len(logs) == 1
    assert amount - targetAmount == after - before
    assert rocketlend.pools(poolId).available == targetAmount

def test_supply_more_other(rocketlendp, RPLToken, rocketVaultImpersonated, other):
    amount = 100 * 10 ** RPLToken.decimals()
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    orig_amount = rocketlend.pools(poolId).available
    grab_RPL(other, amount, RPLToken, rocketVaultImpersonated, rocketlend)
    receipt = rocketlend.changePoolRPL(poolId, 0, orig_amount + amount, sender=other)
    logs = rocketlend.SupplyPool.from_receipt(receipt)
    assert len(logs) == 1
    assert logs[0].total == orig_amount + amount

def test_withdraw_interest_other(partialRepayment, other):
    rocketlend = partialRepayment['rocketlend']
    poolId = partialRepayment['poolId']
    with reverts('revert: a'):
        rocketlend.changePoolRPL(poolId, 1, rocketlend.pools(poolId).available, sender=other)

def test_withdraw_interest(partialRepayment, RPLToken):
    rocketlend = partialRepayment['rocketlend']
    poolId = partialRepayment['poolId']
    lender = partialRepayment['lender']
    supplyBefore = rocketlend.pools(poolId).available
    paidBefore = rocketlend.pools(poolId).interestPaid
    balanceBefore = RPLToken.balanceOf(lender)
    amount = paidBefore // 2
    assert 0 < amount
    receipt = rocketlend.changePoolRPL(poolId, amount, supplyBefore, sender=lender)
    logs = rocketlend.WithdrawInterest.from_receipt(receipt)
    assert len(logs) == 1
    assert RPLToken.balanceOf(lender) == balanceBefore + amount
    assert rocketlend.pools(poolId).available == supplyBefore
    assert rocketlend.pools(poolId).interestPaid == paidBefore - amount

def test_withdraw_interest_and_supply(partialRepayment, RPLToken):
    rocketlend = partialRepayment['rocketlend']
    poolId = partialRepayment['poolId']
    lender = partialRepayment['lender']
    supplyBefore = rocketlend.pools(poolId).available
    paidBefore = rocketlend.pools(poolId).interestPaid
    balanceBefore = RPLToken.balanceOf(lender)
    supplyAmount = paidBefore // 2
    assert 0 < supplyAmount
    receipt = rocketlend.changePoolRPL(poolId, paidBefore, supplyBefore + supplyAmount, sender=lender)
    logs = rocketlend.WithdrawInterest.from_receipt(receipt)
    assert len(logs) == 1
    assert RPLToken.balanceOf(lender) == balanceBefore + paidBefore - supplyAmount
    assert rocketlend.pools(poolId).available == supplyBefore + supplyAmount
    assert rocketlend.pools(poolId).interestPaid == 0

def test_withdraw_interest_and_supply_more_than_available(partialRepayment, RPLToken):
    rocketlend = partialRepayment['rocketlend']
    poolId = partialRepayment['poolId']
    lender = partialRepayment['lender']
    supplyBefore = rocketlend.pools(poolId).available
    paidBefore = rocketlend.pools(poolId).interestPaid
    balanceBefore = RPLToken.balanceOf(lender)
    supplyAmount = paidBefore * 2
    assert balanceBefore < supplyAmount - paidBefore
    with reverts('revert: ERC20: transfer amount exceeds balance'):
        rocketlend.changePoolRPL(poolId, paidBefore, supplyBefore + supplyAmount, sender=lender)

def test_withdraw_interest_and_supply_more_than_approved(partialRepayment, RPLToken, rocketVaultImpersonated):
    rocketlend = partialRepayment['rocketlend']
    poolId = partialRepayment['poolId']
    lender = partialRepayment['lender']
    supplyBefore = rocketlend.pools(poolId).available
    paidBefore = rocketlend.pools(poolId).interestPaid
    grab_RPL(lender, paidBefore, RPLToken, rocketVaultImpersonated, None)
    balanceBefore = RPLToken.balanceOf(lender)
    supplyAmount = paidBefore * 2
    assert balanceBefore >= supplyAmount - paidBefore
    with reverts('revert: ERC20: transfer amount exceeds allowance'):
        rocketlend.changePoolRPL(poolId, paidBefore, supplyBefore + supplyAmount, sender=lender)

def test_withdraw_interest_and_supply_more(partialRepayment, RPLToken, rocketVaultImpersonated):
    rocketlend = partialRepayment['rocketlend']
    poolId = partialRepayment['poolId']
    lender = partialRepayment['lender']
    supplyBefore = rocketlend.pools(poolId).available
    paidBefore = rocketlend.pools(poolId).interestPaid
    grab_RPL(lender, paidBefore, RPLToken, rocketVaultImpersonated, rocketlend)
    balanceBefore = RPLToken.balanceOf(lender)
    supplyAmount = paidBefore * 2
    assert balanceBefore >= supplyAmount - paidBefore
    receipt = rocketlend.changePoolRPL(poolId, paidBefore, supplyBefore + supplyAmount, sender=lender)
    logs = rocketlend.WithdrawInterest.from_receipt(receipt)
    assert len(logs) == 1
    assert RPLToken.balanceOf(lender) == balanceBefore + paidBefore - supplyAmount
    assert rocketlend.pools(poolId).available == supplyBefore + supplyAmount
    assert rocketlend.pools(poolId).interestPaid == 0

### withdrawEtherFromPool

def test_withdraw_ether_from_pool_other(rocketlendp, other):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    with reverts('revert: a'):
        rocketlend.withdrawEtherFromPool(poolId, 20, sender=other)

def test_withdraw_ether_from_pool_none(rocketlendp):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    lender = rocketlendp['lender']
    assert rocketlend.pools(poolId).reclaimed == 0
    with reverts(): # ('Integer underflow'): TODO why this message changed?
        rocketlend.withdrawEtherFromPool(poolId, 20, sender=lender)

#### TODO: successful withdraw of ETH

### forceRepayRPL

def test_force_repay_rpl_not_ended(rocketlendp, borrower1b):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    node = borrower1b['node']
    lender = rocketlendp['lender']
    with reverts('revert: tm'):
        rocketlend.forceRepayRPL(poolId, node, 0, 123, sender=lender)

#### TODO add good repay test and validate amounts

### forceRepayETH

def test_force_repay_eth_other(rocketlendp, borrower1b, other):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    node = borrower1b['node']
    with reverts('revert: a'):
        rocketlend.forceRepayETH(poolId, node, 0, sender=other)

def test_force_repay_eth_not_ended(rocketlendp, borrower1b):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    node = borrower1b['node']
    lender = rocketlendp['lender']
    with reverts('revert: tm'):
        rocketlend.forceRepayETH(poolId, node, 0, sender=lender)

def test_force_eth_repay_noOp(rocketlendp, borrower1b, chain, rocketVaultImpersonated, lender2, RPLToken, accounts):
    node = borrower1b['node']
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    lender = rocketlendp['lender']
    borrower = accounts[rocketlend.borrowers(node).address]

    # borrower has no ETH in rocketlend
    assert rocketlend.borrowers(node).ETH == 0

    # wait for pool to end
    chain.pending_timestamp += round(datetime.timedelta(weeks=2, days=1).total_seconds())

    # check poolId is the first active pool for borrower (i.e. prevIndex == 0)
    assert rocketlend.debtPools(node, rocketlend.debtPools(node, 0).next).poolId == poolId

    with reverts('revert: no'):
        rocketlend.forceRepayETH(poolId, node, 0, sender=lender)

def test_force_eth_repay(rocketlendp, distributedRewards, RPLToken, rocketVaultImpersonated, chain, accounts, rocketNetworkPrices):
    node = distributedRewards['node']
    rocketlend = distributedRewards['rocketlend']
    poolId = rocketlendp['poolId']
    lender = rocketlendp['lender']
    borrower = accounts[rocketlend.borrowers(node).address]

    amount = 50 * 10 ** RPLToken.decimals()
    rocketlend.borrow(poolId, node, 0, amount, sender=borrower)

    # wait for pool to end
    chain.pending_timestamp += round(datetime.timedelta(weeks=2, days=1).total_seconds())

    # update interest to allow get_debt to be (mostly) accrate
    rocketlend.updateInterestDue(poolId, node, sender=borrower)

    prevEth = rocketlend.borrowers(node).ETH
    prevDebt = get_debt(rocketlend, node)

    rocketlend.forceRepayETH(poolId, node, 0, sender=lender)

    afterEth = rocketlend.borrowers(node).ETH
    afterDebt = get_debt(rocketlend, node)

    paidEth = prevEth - afterEth
    assert rocketlend.pools(poolId).reclaimed == paidEth

    paidRPL = (paidEth * 10 ** 18) // rocketNetworkPrices.getRPLPrice()
    assert paidRPL * 0.99 <= prevDebt - afterDebt <= paidRPL * 1.01


### forceClaimMerkleRewards
#### TODO

### forceDistributeRefund

def test_force_distribute_refund_other(rocketlendp, borrower1b, other):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    node = borrower1b['node']
    with reverts('revert: a'):
        rocketlend.forceDistributeRefund(poolId, node, 0, False, [], sender=other)

def test_force_distribute_refund_not_ended(rocketlendp, borrower1b):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    node = borrower1b['node']
    lender = rocketlendp['lender']
    with reverts('revert: tm'):
        rocketlend.forceDistributeRefund(poolId, node, 0, False, [], sender=lender)

#### TODO add good payout test

## Borrower actions

### changeBorrowerAddress
### confirmChangeBorrowerAddress

def test_change_borrower_empty_other(rocketlend, node1, other):
    with reverts('revert: a'):
        rocketlend.changeBorrowerAddress(node1, other, True, sender=other)

def test_change_borrower_to_empty(borrower1):
    rocketlend = borrower1['rocketlend']
    node = borrower1['node']
    borrower = borrower1['borrower']
    with reverts('revert: nu'):
        rocketlend.changeBorrowerAddress(node, nullAddress, False, sender=borrower)
    with reverts('revert: nu'):
        rocketlend.changeBorrowerAddress(node, nullAddress, True, sender=borrower)

def test_change_borrower_to_other(borrower1, other):
    rocketlend = borrower1['rocketlend']
    borrower = borrower1['borrower']
    node = borrower1['node']
    receipt1 = rocketlend.changeBorrowerAddress(node, other, False, sender=borrower)
    logs1 = rocketlend.UpdateBorrower.from_receipt(receipt1)
    assert len(logs1) == 0
    assert rocketlend.borrowers(node).address == borrower
    assert rocketlend.borrowers(node).pending == other
    with reverts('revert: a'):
        rocketlend.confirmChangeBorrowerAddress(node, sender=borrower)
    receipt2 = rocketlend.confirmChangeBorrowerAddress(node, sender=other)
    logs2 = rocketlend.UpdateBorrower.from_receipt(receipt2)
    assert len(logs2) == 1
    assert rocketlend.borrowers(node).address == other
    assert rocketlend.borrowers(node).pending == nullAddress

def test_change_borrower_to_other_force(borrower1, other):
    rocketlend = borrower1['rocketlend']
    borrower = borrower1['borrower']
    node = borrower1['node']
    receipt = rocketlend.changeBorrowerAddress(node, other, True, sender=borrower)
    logs = rocketlend.UpdateBorrower.from_receipt(receipt)
    assert len(logs) == 1
    assert logs[0].old == borrower

def test_change_borrower_2_step_leave_early(rocketlendp, rocketStorage, borrower1, other):
    rocketlend = rocketlendp['rocketlend']
    borrower = borrower1['borrower']
    node = borrower1['node']

    # start 2-step borrower address change
    rocketlend.changeBorrowerAddress(node, other, False, sender=borrower)

    rocketlend.leaveAsBorrower(node, sender=borrower)

    # withdraw address was changed back to borrower
    assert rocketStorage.getNodeWithdrawalAddress(node) == borrower

    # accept the change
    with reverts('revert: a'):
        rocketlend.confirmChangeBorrowerAddress(node, sender=other)


### joinAsBorrower

def test_join_protocol_wrong_pending(rocketlendp, node1):
    rocketlend = rocketlendp['rocketlend']
    with reverts('revert: Confirmation must come from the pending withdrawal address'):
        rocketlend.joinAsBorrower(node1, sender=node1)

def test_join_protocol(rocketlendp, node1, rocketStorage, accounts):
    current_wa = accounts[rocketStorage.getNodeWithdrawalAddress(node1)]
    rocketlend = rocketlendp['rocketlend']
    rocketStorage.setWithdrawalAddress(node1, rocketlend, False, sender=current_wa)
    receipt = rocketlend.joinAsBorrower(node1, sender=current_wa)
    logs = rocketlend.JoinProtocol.from_receipt(receipt)
    assert len(logs) == 1
    assert rocketlend.borrowers(node1).address == current_wa

def test_join_protocol_rplwa_set(rocketlendp, node1, rocketStorage, rocketNodeManager, accounts, other):
    current_wa = accounts[rocketStorage.getNodeWithdrawalAddress(node1)]
    rocketNodeManager.setRPLWithdrawalAddress(node1, other, True, sender=current_wa)
    rocketlend = rocketlendp['rocketlend']
    with reverts('revert: Confirmation must come from the pending withdrawal address'):
        rocketlend.joinAsBorrower(node1, sender=current_wa)

def test_join_protocol_wa_set_prev(rocketlendp, node1, rocketStorage, accounts):
    current_wa = accounts[rocketStorage.getNodeWithdrawalAddress(node1)]
    rocketlend = rocketlendp['rocketlend']
    rocketStorage.setWithdrawalAddress(node1, rocketlend, True, sender=current_wa)
    with reverts('revert: a'):
        rocketlend.joinAsBorrower(node1, sender=current_wa)

def test_join_protocol_wa_set(rocketlendp, node1, rocketStorage, accounts):
    current_wa = accounts[rocketStorage.getNodeWithdrawalAddress(node1)]
    rocketlend = rocketlendp['rocketlend']
    rocketStorage.setWithdrawalAddress(node1, rocketlend, True, sender=current_wa)
    receipt = rocketlend.joinAsBorrower(node1, sender=node1)
    logs = rocketlend.JoinProtocol.from_receipt(receipt)
    assert len(logs) == 1
    assert rocketlend.borrowers(node1).address == node1

def test_join_protocol_other(rocketlendp, node1, rocketStorage, other, accounts):
    current_wa = accounts[rocketStorage.getNodeWithdrawalAddress(node1)]
    rocketlend = rocketlendp['rocketlend']
    rocketStorage.setWithdrawalAddress(node1, rocketlend, False, sender=current_wa)
    receipt = rocketlend.joinAsBorrower(node1, sender=other)
    logs = rocketlend.JoinProtocol.from_receipt(receipt)
    assert len(logs) == 1
    assert rocketlend.borrowers(node1).address == current_wa

def test_join_twice(rocketlendp, borrower1):
    node = borrower1['node']
    borrower = borrower1['borrower']
    rocketlend = rocketlendp['rocketlend']
    with reverts('revert: j'):
        rocketlend.joinAsBorrower(node, sender=borrower)

### leaveAsBorrower

def test_leave_protocol_not_joined(rocketlendp, node1):
    rocketlend = rocketlendp['rocketlend']
    with reverts('revert: a'):
        rocketlend.leaveAsBorrower(node1, sender=node1)

def test_leave_protocol_wrong_sender(rocketlendp, borrower1, other):
    rocketlend = rocketlendp['rocketlend']
    borrower = borrower1['borrower']
    node = borrower1['node']
    with reverts('revert: a'):
        rocketlend.leaveAsBorrower(node, sender=other)

def test_leave_protocol(rocketlendp, borrower1):
    rocketlend = rocketlendp['rocketlend']
    borrower = borrower1['borrower']
    node = borrower1['node']
    receipt = rocketlend.leaveAsBorrower(node, sender=borrower)
    logs = rocketlend.LeaveProtocol.from_receipt(receipt)
    assert len(logs) == 1

def test_leave_with_debt(rocketlendp, borrower1b):
    rocketlend = rocketlendp['rocketlend']
    borrower = borrower1b['borrower']
    node = borrower1b['node']
    with reverts('revert: bo'):
        rocketlend.leaveAsBorrower(node, sender=borrower)

#### TODO: move into repay tests section
def test_leave_after_repaying_with_leftover(rocketlendp, borrower1b, RPLToken, rocketVaultImpersonated, rocketStorage):
    rocketlend = rocketlendp['rocketlend']
    borrower = borrower1b['borrower']
    node = borrower1b['node']
    poolId = borrower1b['poolId']
    buffer = get_debt(rocketlend, node) + 2 * 10 ** RPLToken.decimals() # add 2 RPL buffer for any extra interest
    grab_RPL(borrower, buffer, RPLToken, rocketVaultImpersonated, rocketlend)
    charge_receipt = rocketlend.updateInterestDue(poolId, node, sender=borrower)
    charge_logs = rocketlend.ChargeInterest.from_receipt(charge_receipt)
    debt = borrower1b['amount'] + charge_logs[0].total + 10 ** (RPLToken.decimals() - 1) # more buffer foolishly trying to cover extra interest
    with reverts('revert: o'):
        rocketlend.repay(poolId, node, 0, 0, debt, sender=borrower)
    # TODO:  do a successful test checking some of these things that were true in previous semantics of repay:
    # receipt = rocketlend.repay(poolId, node, 0, debt, sender=borrower)
    # logs = rocketlend.Repay.from_receipt(receipt)
    # assert len(logs) == 1
    # assert logs[0].amount == debt
    # assert logs[0].borrowed == 0
    # assert logs[0].interestDue == 0
    # userBalanceBefore = RPLToken.balanceOf(borrower)
    # rplLeft = rocketlend.borrowers(node).RPL
    # ethLeft = rocketlend.borrowers(node).ETH
    # assert rplLeft > 0
    # # note: you can leave now, despite having some leftover. the only way to get it is to rejoin
    # rocketlend.leaveAsBorrower(node, sender=borrower)
    # with reverts('revert: a'):
    #     rocketlend.withdraw(node, rplLeft, ethLeft, sender=borrower)
    # rocketStorage.setWithdrawalAddress(node, rocketlend, False, sender=borrower)
    # rocketlend.joinAsBorrower(node, sender=borrower)
    # rocketlend.withdraw(node, rplLeft, ethLeft, sender=borrower)
    # assert rocketlend.borrowers(node).RPL == 0
    # assert RPLToken.balanceOf(borrower) == userBalanceBefore + rplLeft

def test_leave_rejoin_wa_unset(rocketlendp, borrower1):
    rocketlend = rocketlendp['rocketlend']
    borrower = borrower1['borrower']
    node = borrower1['node']
    rocketlend.leaveAsBorrower(node, sender=borrower)
    with reverts('revert: Confirmation must come from the pending withdrawal address'):
        rocketlend.joinAsBorrower(node, sender=borrower)

def test_leave_rejoin(rocketlendp, borrower1, rocketStorage):
    rocketlend = rocketlendp['rocketlend']
    borrower = borrower1['borrower']
    node = borrower1['node']
    rocketlend.leaveAsBorrower(node, sender=borrower)
    rocketStorage.setWithdrawalAddress(node, rocketlend, False, sender=borrower)
    receipt = rocketlend.joinAsBorrower(node, sender=borrower)
    logs = rocketlend.JoinProtocol.from_receipt(receipt)
    assert len(logs) == 1
    assert rocketlend.borrowers(node).address == borrower

### stakeRPLFor

def test_stake_rpl_for_other(borrower1, other):
    rocketlend = borrower1['rocketlend']
    node = borrower1['node']
    with reverts('revert: a'):
        rocketlend.stakeRPLFor(node, 0, sender=other)
    with reverts('revert: a'):
        rocketlend.stakeRPLFor(node, 20, sender=other)
    with reverts('revert: a'):
        rocketlend.stakeRPLFor(node, 20, sender=node)

#### TODO: tests for new semantics of stakeRPLFor which uses Rocket Lend balance

# def test_stake_rpl_for_not_approved(borrower1b, RPLToken, rocketVaultImpersonated):
#     rocketlend = borrower1b['rocketlend']
#     node = borrower1b['node']
#     borrower = borrower1b['borrower']
#     amount = 10 * 10 ** RPLToken.decimals()
#     grab_RPL(borrower, amount, RPLToken, rocketVaultImpersonated, None)
#     assert RPLToken.allowance(borrower, rocketlend) < amount
#     with reverts('revert: ERC20: transfer amount exceeds allowance'):
#         rocketlend.stakeRPLFor(node, amount, sender=borrower)
#
# def test_stake_rpl_for_too_much(borrower1b, RPLToken, rocketVaultImpersonated):
#     rocketlend = borrower1b['rocketlend']
#     node = borrower1b['node']
#     borrower = borrower1b['borrower']
#     amount = 10 * 10 ** RPLToken.decimals()
#     RPLToken.approve(rocketlend, amount, sender=borrower)
#     assert RPLToken.balanceOf(borrower) < amount
#     with reverts('revert: ERC20: transfer amount exceeds balance'):
#         rocketlend.stakeRPLFor(node, amount, sender=borrower)
#
# def test_stake_rpl_for(borrower1b, RPLToken, rocketNodeStaking, rocketVaultImpersonated):
#     rocketlend = borrower1b['rocketlend']
#     node = borrower1b['node']
#     borrower = borrower1b['borrower']
#     amount = 20 * 10 ** RPLToken.decimals()
#     grab_RPL(borrower, amount, RPLToken, rocketVaultImpersonated, rocketlend)
#     prev_balance = RPLToken.balanceOf(borrower)
#     prev_RPL = rocketlend.borrowers(node).RPL
#     prev_stake = rocketNodeStaking.getNodeRPLStake(node)
#     receipt = rocketlend.stakeRPLFor(node, amount, sender=borrower)
#     assert RPLToken.balanceOf(borrower) == prev_balance - amount
#     assert rocketlend.borrowers(node).RPL == prev_RPL
#     assert rocketNodeStaking.getNodeRPLStake(node) == prev_stake + amount

### setStakeRPLForAllowed
#### TODO

### unstakeRPL
#### TODO

### borrow

def test_borrow_not_joined(rocketlendp, node1):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    with reverts('revert: a'):
        rocketlend.borrow(poolId, node1, 0, 123, sender=node1)

def test_borrow_from_node(rocketlendp, borrower1):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    node = borrower1['node']
    assert node.address != borrower1['borrower'].address
    with reverts('revert: a'):
        rocketlend.borrow(poolId, node, 0, 123, sender=node)

def test_borrow_limited(rocketlendp, borrower1, rocketNodeStaking, rocketNodeDeposit):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    node = borrower1['node']
    borrower = borrower1['borrower']
    assert rocketNodeStaking.getNodeETHProvided(node) + rocketNodeDeposit.getNodeEthBalance(node) == 0
    with reverts('revert: bl'):
        rocketlend.borrow(poolId, node, 0, 123, sender=borrower)

def test_borrow_against_credit(rocketlendp, borrower1, RPLToken, other, rocketNodeDeposit):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    node = borrower1['node']
    borrower = borrower1['borrower']
    amount = 10 * 10 ** RPLToken.decimals()
    rocketNodeDeposit.depositEthFor(node, value='4 ether', sender=other)
    receipt = rocketlend.borrow(poolId, node, 0, amount, sender=borrower)
    logs = rocketlend.Borrow.from_receipt(receipt)
    assert len(logs) == 1
    log = logs[0]
    assert log['borrowed'] == amount
    assert log['interestDue'] == 0

### repay

def test_repay_partial_supply_unapproved(rocketlendp, RPLToken, rocketVaultImpersonated, borrower1b):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    node = borrower1b['node']
    borrower = borrower1b['borrower']
    supply = 42 * 10 ** RPLToken.decimals()
    grab_RPL(borrower, supply, RPLToken, rocketVaultImpersonated, None)
    with reverts('revert: ERC20: transfer amount exceeds allowance'):
        rocketlend.repay(poolId, node, 0, 0, supply, sender=borrower)

def test_repay_partial_supply_other(rocketlendp, RPLToken, rocketVaultImpersonated, borrower1b, other):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    node = borrower1b['node']
    supply = 42 * 10 ** RPLToken.decimals()
    grab_RPL(other, supply, RPLToken, rocketVaultImpersonated, rocketlend)
    receipt = rocketlend.repay(poolId, node, 0, 0, supply, sender=other)
    logs = rocketlend.Repay.from_receipt(receipt)
    assert len(logs) == 1
    log = logs[0]
    poolState = rocketlend.pools(poolId)
    assert log['interestDue'] == 0
    assert log['borrowed'] == borrower1b['amount'] - (supply - (poolState['interestPaid']))
    assert poolState['borrowed'] == log['borrowed']

def test_repay_withdraw_unauth(rocketlendp, RPLToken, borrower1b, other):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    node = borrower1b['node']
    amount = 2 * 10 ** RPLToken.decimals()
    with reverts('revert: a'):
        rocketlend.repay(poolId, node, 0, amount, 0, sender=other)

def test_repay_cannot_withdraw(rocketlendp, RPLToken, borrower1b):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    node = borrower1b['node']
    borrower = borrower1b['borrower']
    amount = 2 * 10 ** RPLToken.decimals()
    with reverts('revert: The withdrawal cooldown period has not passed'):
        rocketlend.repay(poolId, node, 0, amount, 0, sender=borrower)

def test_repay_by_withdraw(rocketlendp, RPLToken, borrower1b, rocketNodeStaking, chain):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    node = borrower1b['node']
    borrower = borrower1b['borrower']
    amount = 2 * 10 ** RPLToken.decimals()
    stakeBefore = rocketNodeStaking.getNodeRPLStake(node)
    chain.pending_timestamp += round(datetime.timedelta(hours=12, days=28).total_seconds())
    receipt = rocketlend.repay(poolId, node, 0, amount, amount, sender=borrower)
    stakeAfter = rocketNodeStaking.getNodeRPLStake(node)
    logs = rocketlend.Repay.from_receipt(receipt)
    assert len(logs) == 1
    assert stakeBefore - stakeAfter == amount

def test_repay_withdraw_and_supply(rocketlendp, RPLToken, rocketVaultImpersonated, borrower1b, rocketNodeStaking, chain):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    node = borrower1b['node']
    borrower = borrower1b['borrower']
    amount = 2 * 10 ** RPLToken.decimals()
    supply = amount
    grab_RPL(borrower, supply, RPLToken, rocketVaultImpersonated, rocketlend)
    stakeBefore = rocketNodeStaking.getNodeRPLStake(node)
    chain.pending_timestamp += round(datetime.timedelta(hours=12, days=28).total_seconds())
    receipt = rocketlend.repay(poolId, node, 0, amount, amount + supply, sender=borrower)
    stakeAfter = rocketNodeStaking.getNodeRPLStake(node)
    logs = rocketlend.Repay.from_receipt(receipt)
    assert len(logs) == 1
    log = logs[0]
    assert stakeBefore - stakeAfter == amount
    poolState = rocketlend.pools(poolId)
    assert log['interestDue'] == 0
    assert log['borrowed'] == borrower1b['amount'] - (amount + supply - (poolState['interestPaid']))
    assert poolState['borrowed'] == log['borrowed']

def test_repay_withdraw_supply_unauth(rocketlendp, borrower1b, RPLToken, rocketVaultImpersonated, other, chain):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    node = borrower1b['node']
    amount = 200_000
    supply = 400_000
    grab_RPL(other, supply, RPLToken, rocketVaultImpersonated, rocketlend)
    chain.pending_timestamp += round(datetime.timedelta(hours=12, days=28).total_seconds())
    with reverts('revert: a'):
        rocketlend.repay(poolId, node, 0, amount, amount + supply, sender=other)


### transferDebt
#### TODO

### distributeRefund

def test_distribute_rewards_two_MPs_from_other(rocketlend, nodeWithMPsJoined, rocketMinipoolManager, other, accounts, Contract, minipoolABI):
    node = nodeWithMPsJoined['node']
    index = 0
    minipools = []
    indices = []
    while len(minipools) < 2:
        minipool = Contract(rocketMinipoolManager.getNodeMinipoolAt(node, index), abi=minipoolABI)
        if (minipool.getStatus() == stakingStatus):
            minipools.append(minipool)
            indices.append(index)
        index += 1
    index = 2
    for minipool in minipools:
        accounts[1].transfer(minipool, index * 10 ** 18)
        index -= 1
    prev_eth = rocketlend.borrowers(node).ETH
    args = [[index, 1 << Distribute] for index in indices]
    receipt = rocketlend.distributeRefund(node, False, args, sender=other)
    logs = rocketlend.DistributeRefund.from_receipt(receipt)
    assert len(logs) == 1
    assert all(minipool.balance == 0 for minipool in minipools)
    assert rocketlend.borrowers(node).ETH == logs[0].total
    assert prev_eth + logs[0].amount == logs[0].total

#### TODO: test distributing not just rewards: close a minipool and distribute (test from both rocketlend and other (then refund))

def test_other_distribute_minipool_then_refund(rocketlend, nodeWithMPsJoined, other, rocketMinipoolManager, Contract, minipoolABI):
    node = nodeWithMPsJoined['node']
    borrower = nodeWithMPsJoined['borrower']
    index = 0
    minipool = None
    while not minipool:
        minipool = Contract(rocketMinipoolManager.getNodeMinipoolAt(node, index), abi=minipoolABI)
        if (minipool.getStatus() != stakingStatus):
            minipool = None
            index += 1
    other.transfer(minipool, 89 * 10 ** 16) # some fake consensus rewards into the minipool, < 1 ETH
    assert minipool.balance > 0
    minipool.distributeBalance(True, sender=other)
    refundBalance = minipool.getNodeRefundBalance()
    assert minipool.balance == refundBalance
    with reverts('revert: a'):
        rocketlend.distributeRefund(node, False, [[index, 1 << Refund]], sender=other)
    prevBorrowerETH = rocketlend.borrowers(node).ETH
    receipt = rocketlend.distributeRefund(node, False, [[index, 1 << Refund]], sender=borrower)
    logs = rocketlend.DistributeRefund.from_receipt(receipt)
    assert len(logs) == 1
    assert minipool.balance == 0
    assert rocketlend.borrowers(node).ETH == prevBorrowerETH + refundBalance

#### TODO: test multiple minipools refund

### withdraw

def test_withdraw_other(rocketlendp, borrower1b, other):
    rocketlend = rocketlendp['rocketlend']
    node = borrower1b['node']
    with reverts('revert: a'):
        rocketlend.withdraw(node, 1, 1, sender=other)

def test_withdraw_RPL(rocketlendp, RPLToken, borrower1b, chain):
    rocketlend = rocketlendp['rocketlend']
    node = borrower1b['node']
    borrower = borrower1b['borrower']

    # skip RP withdrawal cooldown period
    chain.pending_timestamp += round(datetime.timedelta(days=90).total_seconds())
    # increase RPL held in rocketlend
    amountBorrowed = borrower1b['amount']
    rocketlend.unstakeRPL(node, amountBorrowed, sender=borrower)

    debt = get_debt(rocketlend, node)
    prevBalanceRPL = rocketlend.borrowers(node).RPL
    assert debt <= prevBalanceRPL
    prevBalanceETH = rocketlend.borrowers(node).ETH
    userPrevBalanceRPL = RPLToken.balanceOf(borrower)
    withdrawAmountRPL = prevBalanceRPL - debt
    receipt = rocketlend.withdraw(node, withdrawAmountRPL, 0, sender=borrower)

    afterBalanceRPL = rocketlend.borrowers(node).RPL
    afterBalanceETH = rocketlend.borrowers(node).ETH
    userAfterBalanceRPL = RPLToken.balanceOf(borrower)
    assert userAfterBalanceRPL == userPrevBalanceRPL + withdrawAmountRPL

    deltaBalance = prevBalanceRPL - afterBalanceRPL
    assert deltaBalance == withdrawAmountRPL
    assert prevBalanceETH == afterBalanceETH

    logs = rocketlend.Withdraw.from_receipt(receipt)
    assert len(logs) == 1

    assert logs[0].totalRPL == prevBalanceRPL - withdrawAmountRPL
    assert logs[0].totalETH == prevBalanceETH

def test_withdraw_too_much_RPL(rocketlendp, borrower1b, chain):
    rocketlend = rocketlendp['rocketlend']
    node = borrower1b['node']
    borrower = borrower1b['borrower']

    # skip RP withdrawal cooldown period
    chain.pending_timestamp += round(datetime.timedelta(days=90).total_seconds())
    # increase RPL held in rocketlend
    amountBorrowed = borrower1b['amount']
    rocketlend.unstakeRPL(node, amountBorrowed, sender=borrower)

    debt = get_debt(rocketlend, node)
    prevBalanceRPL = rocketlend.borrowers(node).RPL
    assert debt <= prevBalanceRPL
    withdrawAmountRPL = prevBalanceRPL - debt + 1

    with reverts('revert: d'):
        rocketlend.withdraw(node, withdrawAmountRPL, 0, sender=borrower)

#### TODO: test withdrawing ETH

### depositETHFor

def test_deposit_eth_other(rocketlendp, borrower1, other):
    rocketlend = rocketlendp['rocketlend']
    node = borrower1['node']
    with reverts('revert: a'):
        rocketlend.depositETHFor(node, 20, sender=other)

def test_deposit_eth_none(rocketlendp, borrower1, rocketNodeDeposit):
    rocketlend = rocketlendp['rocketlend']
    node = borrower1['node']
    borrower = borrower1['borrower']
    assert rocketlend.borrowers(node).ETH == 0
    with reverts(): # TODO ('Integer underflow'):
        rocketlend.depositETHFor(node, 20, sender=borrower)

def test_borrow_again(rocketlendp, RPLToken, borrower1b):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    node = borrower1b['node']
    borrower = borrower1b['borrower']
    startTime = borrower1b['receipt'].timestamp
    oneRPL = 10 ** RPLToken.decimals()
    amount = 19 * oneRPL
    receipt = rocketlend.borrow(poolId, node, 0, amount, sender=borrower)
    duration = receipt.timestamp - startTime
    logs = rocketlend.Borrow.from_receipt(receipt)
    assert len(logs) == 1
    log = logs[0]
    assert log['borrowed'] == amount + borrower1b['amount']
    assert log['interestDue'] == borrower1b['amount'] * rocketlend.params(poolId)['interestRate'] * duration // 100 // SECONDS_PER_YEAR

def test_deposit_eth(distributedRewards, rocketNodeDeposit, accounts):
    node = distributedRewards['node']
    rocketlend = distributedRewards['rocketlend']
    borrower = accounts[rocketlend.borrowers(node).address]
    amount = 1 * 10 ** 18
    prev_balance = rocketlend.borrowers(node).ETH
    assert amount < prev_balance
    prev_rp_balance = rocketNodeDeposit.getNodeEthBalance(node)
    receipt = rocketlend.depositETHFor(node, amount, sender=borrower)
    logs = rocketlend.DepositETHFor.from_receipt(receipt)
    assert len(logs) == 1
    assert amount == rocketNodeDeposit.getNodeEthBalance(node) - prev_rp_balance
    assert amount == prev_balance - rocketlend.borrowers(node).ETH

# Full cycle tests
## TODO
