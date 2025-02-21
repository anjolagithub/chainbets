# ChainBets - A8 Chain Esports Betting Platform

## Deployed Contracts (A8 Testnet)
```
BettingPool: 0xdeE81605375942895d01c030a39E4F54B6D8b015
Tournament: 0x989843eF8A89F9F8A55835b535B1775409FDBEbc
CommunityHub: 0x149A3dbb7C92DF2341845e495950EF91E461FbE3
```

## Project Overview
ChainBets is a decentralized esports betting platform built on Ancient8 Chain, enabling users to place bets on esports matches using OP tokens.

## Core Features

### Match Betting
- Create esports matches
- Place bets using OP tokens
- Automated winnings distribution
- Real-time odds calculation

### Tournament System
- Join tournaments with entry fees
- Make predictions on multiple matches
- Earn points for correct predictions
- Tournament-specific leaderboards

### Community Features
- Track user activity
- Referral rewards
- Platform engagement metrics

## Technical Details

### Smart Contracts
1. **BettingPool.sol**
   - Core betting functionality
   - Match creation and management
   - Bet placement and settlement
   - Winnings distribution

2. **Tournament.sol**
   - Tournament creation and management
   - Entry fee handling
   - Match predictions
   - Prize pool distribution

3. **CommunityHub.sol**
   - Community activity tracking
   - User rewards
   - Platform engagement metrics

### Core Functions

```solidity
// Create Match
function createMatch(
    string memory name,
    uint256 startTime,
    uint256 endTime,
    uint256 minBet,
    uint256 maxBet
) external

// Place Bet
function placeBet(
    uint256 matchId,
    uint256 amount,
    uint8 prediction
) external

// Join Tournament
function joinTournament(uint256 tournamentId) external

// Submit Prediction
function submitPrediction(
    uint256 tournamentId,
    uint256 matchId,
    uint8 prediction
) external
```

## Development Setup

### Prerequisites
```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Clone and Setup
git clone <repo>
cd chainbets
forge install
```

### Build and Test
```bash
# Build contracts
forge build

# Run tests
forge test -vvv
```

### Deployment
```bash
# Deploy contracts
forge script script/Deploy.s.sol:DeployChainBets \
    --rpc-url https://rpcv2-testnet.ancient8.gg \
    --broadcast \
    --private-key YOUR_PRIVATE_KEY
```

## Network Details
- **Network**: Ancient8 Testnet
- **RPC URL**: https://rpcv2-testnet.ancient8.gg
- **Chain ID**: 28122024
- **Explorer**: https://scanv2-testnet.ancient8.gg

## Security Features
- Non-custodial betting
- Safe token transfers with SafeERC20
- Secure state management
- Emergency pause functionality

## Frontend Integration
1. Import contract ABIs
2. Connect to Ancient8 Chain
3. Manage user authentication
4. Handle admin functionalities

## License
MIT License

