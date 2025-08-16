# 🎼 Travel Song - Custom EVM Block Explorer

A high-performance, custom-built blockchain explorer for EVM-compatible networks, designed from the ground up for scalability and real-time indexing.
Initially built for the "Kingdom Chain" community chain, it is now a generic EVM block explorer.

## Features

- **Real-time Block Indexing**: Automatically crawls and indexes new blocks every 10 seconds
- **Transaction Tracking**: Comprehensive transaction history with event parsing
- **Address Monitoring**: Track all addresses involved in transactions (sender, receiver, contract creators, event emitters)
- **Smart Contract Support**: Full ABI integration and contract interaction tracking
- **RESTful API**: Clean, documented API endpoints for blockchain data
- **MongoDB Integration**: Robust data storage with optimized schemas
- **Multi-chain Ready**: Built to support any EVM-compatible network
- **Performance Optimized**: Efficient polling and batch processing
- **Discord Integration**: Optional Discord bot for notifications and monitoring

## Architecture

Travel Song is built with a modular architecture:

- **FirstLight**: Core initialization and blockchain connection management
- **Crawler**: Block indexing and transaction processing engine
- **RPC API**: RESTful endpoints for blockchain data queries
- **Fullnode**: Direct blockchain RPC communication layer
- **MongoDB**: Persistent data storage with optimized schemas

## Quick Start

### Prerequisites

- Node.js 18+ 
- MongoDB instance
- Access to EVM RPC endpoint
- Yarn package manager

### Installation

1. **Clone the repository**
   ```bash
   git clone git@github.com:daniportugalgit/travel-song.git
   cd travel-song
   ```

2. **Install dependencies**
   ```bash
   yarn install
   ```

3. **Environment Configuration**
   Create a `.env` file with the following variables:
   ```env
   # Blockchain Configuration
   RPC_URL=https://your-rpc-endpoint
   CHAIN_ID=39916801
   PRIVATE_KEY=your-private-key
   
   # Database Configuration
   MONGODB_URI=mongodb://localhost:27017/travel-song
   
   # Application Settings
   PORT=3000
   APP_NAME=Travel Song
   ENV=development
   POLLING_INTERVAL_MS=10000
   POLLING_SIZE=10
   
   # Optional: Discord Integration
   DISCORD_TOKEN=your-discord-token
   DISCORD_CLIENT_ID=your-discord-client-id
   DISCORD_ENV=development
   
   # API Endpoints
   POST_ENDPOINTS=["rpc"]
   GET_ENDPOINTS=["health"]
   
   # System Configuration
   RESET_DATABASE=false
   LOG_VARIABLES=RPC_URL,CHAIN_ID,ENV
   ```

4. **Start the application**
   ```bash
   # Development mode with auto-restart
   yarn dev
   
   # Production mode
   node src/index.js
   ```

## API Endpoints

### RPC Endpoint
**POST** `/rpc`
Main endpoint for blockchain data queries. Accepts standard RPC methods.

**Request Body:**
```json
{
  "method": "txsByAddress",
  "params": {
    "address": "0x...",
    "page": 1,
    "limit": 25,
    "includeEvents": true
  }
}
```

### Available Methods

#### `txsByAddress`
Get transactions for a specific address with pagination.

**Parameters:**
- `address` (string): Ethereum address to query
- `page` (number): Page number for pagination (default: 1)
- `limit` (number): Number of transactions per page (default: 25)
- `includeEvents` (boolean): Include event emitter addresses (default: false)
- `from` (string): Filter transactions from specific block (optional)

**Response:**
```json
{
  "success": true,
  "txList": [...],
  "totalCount": 150,
  "currentBlockHeight": 12345
}
```

#### `latestTxs`
Get the latest transactions from the blockchain.

**Parameters:**
- `limit` (number): Number of transactions to return (default: 10)

#### `latestSummary`
Get a summary of the latest block and transactions.

**Parameters:**
- `limit` (number): Number of transactions to include (default: 10)

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `RPC_URL` | EVM RPC endpoint URL | Required |
| `CHAIN_ID` | Blockchain network ID | Required |
| `PRIVATE_KEY` | Wallet private key for signing | Required |
| `MONGODB_URI` | MongoDB connection string | Required |
| `PORT` | Application port | 3000 |
| `POLLING_INTERVAL_MS` | Block polling interval | 10000 |
| `POLLING_SIZE` | Number of blocks to process per cycle | 10 |
| `RESET_DATABASE` | Reset database on startup | false |

### Database Schemas

The application uses three main MongoDB collections:

- **transactions**: All indexed transaction data
- **latestblocks**: Latest processed block information
- **balances**: Address balance tracking

## Running in Production

### PM2 Process Manager
```bash
# Install PM2 globally
npm install -g pm2

# Start the application
pm2 start src/index.js --name "travel-song"

# Monitor the application
pm2 monit

# View logs
pm2 logs travel-song
```

## Monitoring & Debugging

### Logging
The application provides comprehensive logging with color-coded output:
- 🎼 Transaction processing
- ✨ Initialization events
- 🌍 Blockchain connection status
- ❌ Error handling

### Health Checks
Monitor the application health via the root endpoint:
```bash
curl http://localhost:3000/
# Response: Travel Song online
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built with [Ethers.js](https://ethers.org/) for blockchain interaction
- MongoDB for robust data storage
- Express.js for the REST API framework

## Support

For questions, issues, or contributions:
- Open an issue on GitHub
- Contact the development team
- Check the documentation for common solutions

---

**Travel Song** - Exploring the blockchain, one block at a time 🎼
