# Scattering Contracts

This project demonstrates a Hardhat and Foundry use case. It comes with a sample contract, a test for that contract, and a script that deploys that contract.

## Installation

1. Clone the repo
2. [Install foundry](https://github.com/foundry-rs/foundry)

```
git clone https://github.com/scatteringlabs/scattering-contracts
cd scattering-contracts
pnpm install
forge install
```

## Setup

### .env

Copy `.env` from `.env.example`
abd fill in all the variables in `.env`

### hardhat.config.ts

Modify `namedAccounts` in `hardhat.config.ts` and add networks if necessary.

## Test

```
forge test
forge test -vvv
```

## Flatten

```bash
mkdir flat
npx hardhat flatten <path-to-contract> >> flat/<flat-contract-name>.sol
npx hardhat flatten contracts/Scattering.sol >> flat/Scattering.sol
```

## Deployment

```
npx hardhat run --network <NETWORK> scripts/01-deploy-scr.ts
```

## Other

```
slither .
```

## License

GNU General Public License v3.0 or later

See [COPYING](./COPYING) to see the full text.
