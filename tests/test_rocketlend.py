import time
import datetime
import pytest
from eth_utils import keccak
from ape import reverts

rocketStorageAddresses = dict(
        mainnet='0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46',
        holesky='0x594Fb75D3dc2DFa0150Ad03F99F97817747dd4E1')

SECONDS_PER_YEAR = 365 * 24 * 60 * 60

nullAddress = '0x0000000000000000000000000000000000000000'

@pytest.fixture()
def rocketStorage(chain, Contract):
    return Contract(rocketStorageAddresses[chain.provider.network.name.removesuffix('-fork')])

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
def rocketNodeStaking(rocketStorage, Contract):
    return Contract(rocketStorage.getAddress(keccak('contract.addressrocketNodeStaking'.encode())))

@pytest.fixture()
def rocketNodeDeposit(rocketStorage, Contract):
    return Contract(rocketStorage.getAddress(keccak('contract.addressrocketNodeDeposit'.encode())))

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
def rocketlend(project, rocketStorage, deployer):
    return deployer.deploy(project.rocketlend, rocketStorage)

def test_RPL_token_address(rocketlend, RPLToken):
    assert rocketlend.RPL() == RPLToken.address

def test_rocketstorage_address(rocketlend, rocketStorage):
    assert rocketlend.rocketStorage() == rocketStorage.address

def test_create_pool_unregistered(rocketlend, other):
    with reverts('revert: auth'):
        rocketlend.createPool(dict(lender=0, interestRate=0, endTime=0), 0, 0, [0], sender=other)

def test_register_lender1(rocketlend, lender1):
    nextId = rocketlend.nextLenderId()
    assert nextId == 0
    receipt = rocketlend.registerLender(sender=lender1)
    assert receipt.return_value == nextId
    logs = rocketlend.RegisterLender.from_receipt(receipt)
    assert len(logs) == 1
    assert logs[0]['id'] == nextId
    assert logs[0]['address'] == lender1

def test_change_borrower_other(rocketlend, node1, other):
    with reverts('revert: auth'):
        rocketlend.changeBorrowerAddress(node1, other, True, sender=other)

@pytest.fixture()
def rocketlendReg1(rocketlend, lender1):
    receipt = rocketlend.registerLender(sender=lender1)
    log = rocketlend.RegisterLender.from_receipt(receipt)[0]
    return dict(rocketlend=rocketlend,
                lenderId=log.id,
                lenderAddress=log.address)

def test_create_expired_pool(rocketlendReg1, lender1):
    params = dict(lender=rocketlendReg1["lenderId"], interestRate=0, endTime=0)
    rocketlend = rocketlendReg1["rocketlend"]
    receipt = rocketlend.createPool(params, 0, 0, [0], sender=lender1)
    logs = rocketlend.CreatePool.from_receipt(receipt)
    assert len(logs) == 1
    assert logs[0]['params'] == list(params.values())

def test_change_lender_address_other(rocketlendReg1, other):
    rocketlend = rocketlendReg1["rocketlend"]
    lenderId = rocketlendReg1["lenderId"]
    lenderAddress = rocketlendReg1["lenderAddress"]
    with reverts('revert: auth'):
        rocketlend.changeLenderAddress(lenderId, lenderAddress, False, sender=other)
    with reverts('revert: auth'):
        rocketlend.changeLenderAddress(lenderId, other, False, sender=other)
    with reverts('revert: auth'):
        rocketlend.changeLenderAddress(lenderId, lenderAddress, True, sender=other)

def test_change_lender_address(rocketlendReg1, lender1, other):
    rocketlend = rocketlendReg1["rocketlend"]
    lenderId = rocketlendReg1["lenderId"]
    lenderAddress = rocketlendReg1["lenderAddress"]
    assert lender1 == lenderAddress
    rocketlend.changeLenderAddress(lenderId, other, False, sender=lender1)
    assert rocketlend.lenderAddress(lenderId) == lender1
    assert rocketlend.pendingLenderAddress(lenderId) == other
    with reverts('revert: auth'):
        rocketlend.confirmChangeLenderAddress(lenderId, sender=lender1)
    receipt = rocketlend.confirmChangeLenderAddress(lenderId, sender=other)
    assert rocketlend.lenderAddress(lenderId) == other
    assert rocketlend.pendingLenderAddress(lenderId) == nullAddress
    logs = rocketlend.UpdateLender.from_receipt(receipt)
    assert len(logs) == 1

def test_change_lender_address_force(rocketlendReg1, lender1, other):
    rocketlend = rocketlendReg1["rocketlend"]
    lenderId = rocketlendReg1["lenderId"]
    lenderAddress = rocketlendReg1["lenderAddress"]
    receipt = rocketlend.changeLenderAddress(lenderId, other, True, sender=lender1)
    assert rocketlend.lenderAddress(lenderId) == other
    assert rocketlend.pendingLenderAddress(lenderId) == nullAddress

@pytest.fixture()
def rocketlendReg2(rocketlendReg1, lender2):
    rocketlendReg1["rocketlend"].registerLender(sender=lender2)
    return rocketlendReg1["rocketlend"]

@pytest.fixture()
def rocketlendf(rocketlendReg2, node3):
    rocketlendReg2.registerLender(sender=node3)
    return rocketlendReg2

def time_from_now(**kwargs):
    return round(time.time() + datetime.timedelta(**kwargs).total_seconds())

def test_create_pool(rocketlendf, lender2):
    params = dict(lender=1, interestRate=1, endTime=time_from_now(days=3))
    receipt = rocketlendf.createPool(params, 0, 0, [0], sender=lender2)
    logs = rocketlendf.CreatePool.from_receipt(receipt)
    assert len(logs) == 1

def grab_RPL(who, amount, RPLToken, rocketVaultImpersonated, rocketlend):
    RPLToken.transfer(who, amount, sender=rocketVaultImpersonated)
    if rocketlend:
        RPLToken.approve(rocketlend, amount, sender=who)

def test_create_pool_with_supply(rocketlendf, RPLToken, rocketVaultImpersonated, lender2):
    amount = 20 * 10 ** RPLToken.decimals()
    grab_RPL(lender2, amount, RPLToken, rocketVaultImpersonated, rocketlendf)
    params = dict(lender=1, interestRate=1, endTime=time_from_now(days=3))
    receipt = rocketlendf.createPool(params, amount, 0, [0], sender=lender2)
    logs = rocketlendf.CreatePool.from_receipt(receipt)
    assert len(logs) == 1

@pytest.fixture()
def rocketlendp(rocketlendf, RPLToken, rocketVaultImpersonated, lender2):
    amount = 200 * 10 ** RPLToken.decimals()
    grab_RPL(lender2, amount, RPLToken, rocketVaultImpersonated, rocketlendf)
    endTime=time_from_now(weeks=2)
    params = dict(lender=1, interestRate=10, endTime=endTime)
    receipt = rocketlendf.createPool(params, amount, 0, [0], sender=lender2)
    poolId = rocketlendf.CreatePool.from_receipt(receipt)[0].id
    return dict(receipt=receipt, lenderId=1, lender=lender2, rocketlend=rocketlendf, poolId=poolId, endTime=endTime, amount=amount)

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

def test_supply_set(rocketlendp):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    receipt = rocketlendp['receipt']
    log = rocketlend.SupplyPool.from_receipt(receipt)[0]
    assert log.amount == log.total
    assert rocketlend.pools(poolId).available == log.amount

def test_allowed_to_borrow_set(rocketlendp):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    lender = rocketlendp['lender']
    assert rocketlend.allowedToBorrow(poolId, nullAddress)
    assert not rocketlend.allowedToBorrow(poolId, lender)

def test_supply_more_other(rocketlendp, RPLToken, rocketVaultImpersonated, other):
    amount = 100 * 10 ** RPLToken.decimals()
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    orig_receipt = rocketlendp['receipt']
    orig_amount = rocketlend.SupplyPool.from_receipt(orig_receipt)[0].amount
    grab_RPL(other, amount, RPLToken, rocketVaultImpersonated, rocketlend)
    receipt = rocketlend.supplyPool(poolId, amount, sender=other)
    logs = rocketlend.SupplyPool.from_receipt(receipt)
    assert len(logs) == 1
    assert logs[0].total == orig_amount + amount

def test_withdraw_other(rocketlendp, other):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    amount = rocketlendp['amount'] // 2
    with reverts('revert: auth'):
        rocketlend.withdrawFromPool(poolId, amount, sender=other)

def test_withdraw_unborrowed(rocketlendp, RPLToken):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    lender = rocketlendp['lender']
    amount = rocketlendp['amount']
    before = RPLToken.balanceOf(lender)
    receipt = rocketlend.withdrawFromPool(poolId, amount // 3, sender=lender)
    after = RPLToken.balanceOf(lender)
    logs = rocketlend.WithdrawFromPool.from_receipt(receipt)
    assert len(logs) == 1
    assert logs[0].amount == after - before
    assert logs[0].total == amount - logs[0].amount
    assert rocketlend.pools(poolId).available == logs[0].total

def test_borrow_not_joined(rocketlendp, node1):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    with reverts('revert: auth'):
        rocketlend.borrow(poolId, node1, 123, sender=node1)

def test_join_protocol_wrong_pending(rocketlendp, node1):
    rocketlend = rocketlendp['rocketlend']
    with reverts():
        rocketlend.joinAsBorrower(node1, sender=node1)

def test_join_protocol(rocketlendp, node1, rocketStorage, accounts):
    current_wa = accounts[rocketStorage.getNodeWithdrawalAddress(node1)]
    rocketlend = rocketlendp['rocketlend']
    rocketStorage.setWithdrawalAddress(node1, rocketlend, False, sender=current_wa)
    receipt = rocketlend.joinAsBorrower(node1, sender=current_wa)
    logs = rocketlend.JoinProtocol.from_receipt(receipt)
    assert len(logs) == 1
    assert logs[0]['node'] == node1
    assert rocketlend.borrowers(node1).address == current_wa

def test_join_protocol_rplwa_set(rocketlendp, node1, rocketStorage, rocketNodeManager, accounts, other):
    current_wa = accounts[rocketStorage.getNodeWithdrawalAddress(node1)]
    rocketNodeManager.setRPLWithdrawalAddress(node1, other, True, sender=current_wa)
    rocketlend = rocketlendp['rocketlend']
    with reverts():
        rocketlend.joinAsBorrower(node1, sender=current_wa)

def test_join_protocol_wa_set_prev(rocketlendp, node1, rocketStorage, accounts):
    current_wa = accounts[rocketStorage.getNodeWithdrawalAddress(node1)]
    rocketlend = rocketlendp['rocketlend']
    rocketStorage.setWithdrawalAddress(node1, rocketlend, True, sender=current_wa)
    with reverts('revert: auth'):
        rocketlend.joinAsBorrower(node1, sender=current_wa)

def test_join_protocol_wa_set(rocketlendp, node1, rocketStorage, accounts):
    current_wa = accounts[rocketStorage.getNodeWithdrawalAddress(node1)]
    rocketlend = rocketlendp['rocketlend']
    rocketStorage.setWithdrawalAddress(node1, rocketlend, True, sender=current_wa)
    receipt = rocketlend.joinAsBorrower(node1, sender=node1)
    logs = rocketlend.JoinProtocol.from_receipt(receipt)
    assert len(logs) == 1
    assert logs[0]['node'] == node1
    assert rocketlend.borrowers(node1).address == node1

def test_join_protocol_other(rocketlendp, node1, rocketStorage, other, accounts):
    current_wa = accounts[rocketStorage.getNodeWithdrawalAddress(node1)]
    rocketlend = rocketlendp['rocketlend']
    rocketStorage.setWithdrawalAddress(node1, rocketlend, False, sender=current_wa)
    receipt = rocketlend.joinAsBorrower(node1, sender=other)
    logs = rocketlend.JoinProtocol.from_receipt(receipt)
    assert len(logs) == 1
    assert rocketlend.borrowers(node1).address == current_wa

@pytest.fixture()
def borrower1(rocketlendp, node1, rocketStorage, accounts):
    current_wa = accounts[rocketStorage.getNodeWithdrawalAddress(node1)]
    rocketlend = rocketlendp['rocketlend']
    rocketStorage.setWithdrawalAddress(node1, rocketlend, False, sender=current_wa)
    rocketlend.joinAsBorrower(node1, sender=current_wa)
    return dict(node=node1, borrower=current_wa)

def test_join_twice(rocketlendp, borrower1):
    node = borrower1['node']
    borrower = borrower1['borrower']
    rocketlend = rocketlendp['rocketlend']
    with reverts('revert: j'):
        rocketlend.joinAsBorrower(node, sender=borrower)

def test_leave_protocol_not_joined(rocketlendp, node1):
    rocketlend = rocketlendp['rocketlend']
    with reverts('revert: auth'):
        rocketlend.leaveAsBorrower(node1, sender=node1)

def test_leave_protocol_wrong_sender(rocketlendp, borrower1, other):
    rocketlend = rocketlendp['rocketlend']
    borrower = borrower1['borrower']
    node = borrower1['node']
    with reverts('revert: auth'):
        rocketlend.leaveAsBorrower(node, sender=other)

def test_leave_protocol(rocketlendp, borrower1):
    rocketlend = rocketlendp['rocketlend']
    borrower = borrower1['borrower']
    node = borrower1['node']
    receipt = rocketlend.leaveAsBorrower(node, sender=borrower)
    logs = rocketlend.LeaveProtocol.from_receipt(receipt)
    assert len(logs) == 1
    assert logs[0]['node'] == node

def test_leave_rejoin_wa_unset(rocketlendp, borrower1):
    rocketlend = rocketlendp['rocketlend']
    borrower = borrower1['borrower']
    node = borrower1['node']
    rocketlend.leaveAsBorrower(node, sender=borrower)
    with reverts():
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

def test_borrow_from_node(rocketlendp, borrower1):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    node = borrower1['node']
    assert node.address != borrower1['borrower'].address
    with reverts('revert: auth'):
        rocketlend.borrow(poolId, node, 123, sender=node)

def test_borrow_limited(rocketlendp, borrower1, rocketNodeStaking, rocketNodeDeposit):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    node = borrower1['node']
    borrower = borrower1['borrower']
    assert rocketNodeStaking.getNodeETHProvided(node) + rocketNodeDeposit.getNodeEthBalance(node) == 0
    with reverts('revert: lim'):
        rocketlend.borrow(poolId, node, 123, sender=borrower)

def test_borrow_against_credit(rocketlendp, borrower1, RPLToken, other, rocketNodeDeposit):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    node = borrower1['node']
    borrower = borrower1['borrower']
    amount = 10 * 10 ** RPLToken.decimals()
    rocketNodeDeposit.depositEthFor(node, value='4 ether', sender=other)
    receipt = rocketlend.borrow(poolId, node, amount, sender=borrower)
    logs = rocketlend.Borrow.from_receipt(receipt)
    assert len(logs) == 1
    log = logs[0]
    assert log['pool'] == poolId
    assert log['node'] == node
    assert log['amount'] == amount
    assert log['borrowed'] == amount
    assert log['interestDue'] == 0

@pytest.fixture()
def borrower1b(rocketlendp, RPLToken, rocketNodeDeposit, borrower1, other):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    node = borrower1['node']
    borrower = borrower1['borrower']
    amount = 50 * 10 ** RPLToken.decimals()
    rocketNodeDeposit.depositEthFor(node, value='8 ether', sender=other)
    receipt = rocketlend.borrow(poolId, node, amount, sender=borrower)
    return dict(borrower1, amount=amount, receipt=receipt)

def test_view_borrowed(rocketlendp, borrower1b):
    rocketlend = rocketlendp['rocketlend']
    node = borrower1b['node']
    assert rocketlend.borrowers(node)['borrowed'] == borrower1b['amount']

def test_force_repay_not_ended(rocketlendp, borrower1b):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    node = borrower1b['node']
    lender = rocketlendp['lender']
    with reverts('revert: term'):
        rocketlend.forceRepayRPL(poolId, node, 123, sender=lender)
    with reverts('revert: term'):
        rocketlend.forceRepayETH(poolId, node, sender=lender)

def test_leave_with_debt(rocketlendp, borrower1b):
    rocketlend = rocketlendp['rocketlend']
    borrower = borrower1b['borrower']
    node = borrower1b['node']
    with reverts('revert: b'):
        rocketlend.leaveAsBorrower(node, sender=borrower)

def test_repay_partial_supply_unapproved(rocketlendp, RPLToken, rocketVaultImpersonated, borrower1b):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    node = borrower1b['node']
    borrower = borrower1b['borrower']
    supply = 42 * 10 ** RPLToken.decimals()
    grab_RPL(borrower, supply, RPLToken, rocketVaultImpersonated, None)
    with reverts('revert: ERC20: transfer amount exceeds allowance'):
        rocketlend.repay(poolId, node, 0, supply, sender=borrower)

def test_repay_partial_supply_other(rocketlendp, RPLToken, rocketVaultImpersonated, borrower1b, other):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    node = borrower1b['node']
    supply = 42 * 10 ** RPLToken.decimals()
    grab_RPL(other, supply, RPLToken, rocketVaultImpersonated, rocketlend)
    receipt = rocketlend.repay(poolId, node, 0, supply, sender=other)
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
    with reverts('revert: auth'):
        rocketlend.repay(poolId, node, amount, 0, sender=other)

def test_repay_cannot_withdraw(rocketlendp, RPLToken, borrower1b):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    node = borrower1b['node']
    borrower = borrower1b['borrower']
    amount = 2 * 10 ** RPLToken.decimals()
    with reverts():
        rocketlend.repay(poolId, node, amount, 0, sender=borrower)

def test_repay_by_withdraw(rocketlendp, RPLToken, borrower1b, rocketNodeStaking, chain):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    node = borrower1b['node']
    borrower = borrower1b['borrower']
    amount = 2 * 10 ** RPLToken.decimals()
    stakeBefore = rocketNodeStaking.getNodeRPLStake(node)
    chain.pending_timestamp += round(datetime.timedelta(hours=12, days=28).total_seconds())
    receipt = rocketlend.repay(poolId, node, amount, 0, sender=borrower)
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
    receipt = rocketlend.repay(poolId, node, amount, supply, sender=borrower)
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
    with reverts('revert: auth'):
        rocketlend.repay(poolId, node, amount, supply, sender=other)

def test_borrow_again(rocketlendp, RPLToken, borrower1b):
    rocketlend = rocketlendp['rocketlend']
    poolId = rocketlendp['poolId']
    node = borrower1b['node']
    borrower = borrower1b['borrower']
    startTime = borrower1b['receipt'].timestamp
    oneRPL = 10 ** RPLToken.decimals()
    amount = 19 * oneRPL
    receipt = rocketlend.borrow(poolId, node, amount, sender=borrower)
    duration = receipt.timestamp - startTime
    logs = rocketlend.Borrow.from_receipt(receipt)
    assert len(logs) == 1
    log = logs[0]
    assert log['pool'] == poolId
    assert log['node'] == node
    assert log['amount'] == amount
    assert log['borrowed'] == amount + borrower1b['amount']
    assert log['interestDue'] == borrower1b['amount'] * rocketlend.params(poolId)['interestRate'] * duration // 100 // SECONDS_PER_YEAR
