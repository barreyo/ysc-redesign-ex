# Ysc

## Getting Started

### Prerequisites

- Elixir and Erlang installed
- Docker and Docker Compose installed
- Stripe API keys (see Environment Variables section below)

### Initial Setup

1. **Set up environment variables** (see Environment Variables section below) - either export them or create a `.env` file

2. **Set up local development environment**:

   ```bash
   make dev-setup
   ```

   This command will:

   - Install dependencies
   - Start local development services (database, S3, etc.)
   - Run database migrations
   - Seed the database with initial data

3. **Start the development server**:
   ```bash
   make dev
   ```

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Environment Variables

**Important:** All Stripe environment variables must be set before running `make dev`. You can either export them in your shell or use a `.env` file.

### Required Stripe Configuration

- `STRIPE_SECRET` - Your Stripe secret key
- `STRIPE_PUBLIC_KEY` - Your Stripe publishable key
- `STRIPE_WEBHOOK_SECRET` - Your Stripe webhook secret

You can get these from your [Stripe Dashboard](https://dashboard.stripe.com/apikeys).

### Setting Environment Variables

You can set these variables in one of two ways:

#### Option 1: Export in your shell

```bash
export STRIPE_SECRET="sk_test_..."
export STRIPE_PUBLIC_KEY="pk_test_..."
export STRIPE_WEBHOOK_SECRET="whsec_..."
```

#### Option 2: Create a `.env` file

Create a `.env` file in the project root:

```bash
STRIPE_SECRET=sk_test_...
STRIPE_PUBLIC_KEY=pk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...
```

**Note:** Exported environment variables take precedence over values in the `.env` file. The `make dev` command will automatically load variables from `.env` if the file exists.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

- Official website: https://www.phoenixframework.org/
- Guides: https://hexdocs.pm/phoenix/overview.html
- Docs: https://hexdocs.pm/phoenix
- Forum: https://elixirforum.com/c/phoenix-forum
- Source: https://github.com/phoenixframework/phoenix
