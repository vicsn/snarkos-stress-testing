# Artillery Load Tests

This repository contains Artillery test scripts for stress testing the specific endpoint.

## Prerequisites

- Node.js (LTS version)

## Setup

1. **Install dependencies**:
   ```bash
   npm install
   ```

## Running Tests

To run the test script for the designated endpoint, execute:

```bash
npm run test
```

This command uses the test script configured in `package.json` to execute Artillery with the specific test settings.

## Analyzing Results

To save and review the results in a readable format:

```bash
npm run report
```