import { readFileSync } from 'fs';
import {
  Contract,
  ContractFactory,
  ContractUtils,
  Provider,
  Wallet,
  WalletUnlocked,
} from 'fuels';

import { HyperlaneMailboxAbi__factory } from '../types/factories/HyperlaneMailboxAbi__factory';

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

  console.log('Contract ID:');
  console.log({
    mailbox: mailbox.id.toHexString(),
  });

  if (SEND_MESSAGE) {
    await dispatchMessage(mailbox);
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

async function deployOrGetMailbox(wallet: WalletUnlocked): Promise<Contract> {
  const bytecode = readFileSync(
    '../contracts/hyperlane-mailbox/out/debug/hyperlane-mailbox.bin',
  );

  const factory = new ContractFactory(
    bytecode,
    HyperlaneMailboxAbi__factory.abi,
    wallet,
  );

  const expectedMailboxContractId = ContractUtils.getContractId(
    bytecode,
    CONTRACT_SALT,
    ContractUtils.getContractStorageRoot([]),
  );

  const maybeDeployedContract = await wallet.provider.getContract(
    expectedMailboxContractId,
  );

  // If the contract's already been deployed, just get the existing one without deploying
  if (maybeDeployedContract) {
    console.log('Contract already deployed');
    return new Contract(
      expectedMailboxContractId,
      HyperlaneMailboxAbi__factory.abi,
      wallet,
    );
  }

  console.log('Deploying contract...');
  return factory.deployContract({
    salt: CONTRACT_SALT,
  });
}

async function dispatchMessage(mailbox: Contract) {
  const dispatchTx = mailbox.functions.dispatch(
    420,
    '0x6900000000000000000000000000000000000000000000000000000000000069',
    // TODO: it seems like fuels-ts may not be accurately
    // encoding this array into Vec<u8>, we should investigate
    [1, 2, 3, 5, 6],
  );

  // To avoid issues with fuels-ts trying to decode logs that it's unable to yet,
  // send the transaction request rather than using `dispatchTx.call()`.

  const txRequest = await dispatchTx.getTransactionRequest();
  const txResponse = await mailbox.provider!.sendTransaction(txRequest);

  console.log('Dispatched message', await txResponse.wait());
}

main().catch((err) => console.error('Error:', err));
