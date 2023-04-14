import { readFileSync } from 'fs';
import {
  Contract,
  ContractFactory,
  ContractUtils,
  Provider,
  StorageSlot,
  Wallet,
  WalletUnlocked,
} from 'fuels';

import { HyperlaneMailboxAbi__factory } from '../types/factories/HyperlaneMailboxAbi__factory';
import { HyperlaneMsgRecipientTestAbi__factory } from '../types/factories/HyperlaneMsgRecipientTestAbi__factory';

// First default account from running fuel-client locally:
//   Address: 0x6b63804cfbf9856e68e5b6e7aef238dc8311ec55bec04df774003a2c96e0418e
//   Balance: 10000000
const PRIVATE_KEY =
  '0xde97d8624a438121b86a1956544bd72ed68cd69f2c99555b08b1e8c51ffd511c';

// Rather than generating a new random contract ID each time, we can use a consistent salt
// to have a deterministic ID as long as the bytecode of the contract stays the same.
// See here to understand how contract IDs are generated:
// https://fuellabs.github.io/fuel-specs/master/protocol/id/contract.html
const CONTRACT_SALT =
  '0x0000000000000000000000000000000000000000000000000000000000000000';

// TODO: better command line arg support
const SEND_MESSAGE = process.argv[2] === 'send-message';

// Deploys the mailbox if it's not been deployed already.
// Sends a dummy message if the first param to the command is `send-message`.
async function main() {
  const provider = new Provider('http://127.0.0.1:4000/graphql');
  const wallet = Wallet.fromPrivateKey(PRIVATE_KEY, provider);

  const mailbox = await deployOrGetMailbox(wallet);
  const testRecipient = await deployOrGetTestRecipient(wallet);

  console.log('Contract IDs:');
  console.log({
    mailbox: mailbox.id.toHexString(),
    testRecipient: testRecipient.id.toHexString(),
  });

  if (SEND_MESSAGE) {
    await dispatchMessage(mailbox, testRecipient);
  }

  try {
    console.log(
      'Current latest checkpoint:',
      (await mailbox.functions.latest_checkpoint().simulate()).value,
    );
  } catch (err) {
    console.log(
      'Error getting latest checkpoint - this is expected if no messages have been sent yet',
    );
  }
}

async function deployOrGetContract(
  wallet: WalletUnlocked,
  factory: ContractFactory,
  storageSlots: StorageSlot[] = [],
): Promise<Contract> {
  const expectedId = ContractUtils.getContractId(
    factory.bytecode,
    CONTRACT_SALT,
    ContractUtils.getContractStorageRoot(storageSlots),
  );

  const maybeDeployedContract = await wallet.provider.getContract(
    expectedId,
  );

  // If the contract's already been deployed, just get the existing one without deploying
  if (maybeDeployedContract) {
    console.log('Contract already deployed');
    return new Contract(
      expectedId,
      factory.interface.abi!,
      wallet,
    );
  }

  console.log('Deploying contract...');
  return factory.deployContract({
    salt: CONTRACT_SALT,
  });
}

async function deployOrGetMailbox(wallet: WalletUnlocked): Promise<Contract> {
  const factory = new ContractFactory(
    readFileSync(
      '../contracts/hyperlane-mailbox/out/debug/hyperlane-mailbox.bin',
    ),
    HyperlaneMailboxAbi__factory.abi,
    wallet,
  );

  return deployOrGetContract(
    wallet,
    factory,
  );
}

async function deployOrGetTestRecipient(wallet: WalletUnlocked): Promise<Contract> {
  const factory = new ContractFactory(
    readFileSync(
      '../contracts/hyperlane-msg-recipient-test/out/debug/hyperlane-msg-recipient-test.bin',
    ),
    HyperlaneMsgRecipientTestAbi__factory.abi,
    wallet,
  );

  return deployOrGetContract(
    wallet,
    factory,
  );
}

async function dispatchMessage(mailbox: Contract, testRecipient: Contract) {
  // Dispatch a message via the testRecipient, which takes in a Vec<u8> body
  // instead of the Mailbox's Bytes body, which isn't supported by fuels-ts yet.
  const dispatchTx = testRecipient.functions.dispatch(
    // fuels-ts only encodes Vecs correctly when they are the first parameter (lol)
    // See https://github.com/FuelLabs/fuels-ts/issues/881
    [1, 2, 3, 5, 6],
    mailbox.id.toB256(),
    420,
    '0x6900000000000000000000000000000000000000000000000000000000000069',
  )
  .addContracts([mailbox]);

  // To avoid issues with fuels-ts trying to decode logs that it's unable to yet,
  // send the transaction request rather than using `dispatchTx.call()`.

  const txRequest = await dispatchTx.getTransactionRequest();
  const txResponse = await mailbox.provider!.sendTransaction(txRequest);

  console.log('Dispatched message', await txResponse.wait());
}

main().catch((err) => console.error('Error:', err));
