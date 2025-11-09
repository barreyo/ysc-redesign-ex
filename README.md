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

### Optional Configuration

- `RADAR_PUBLIC_KEY` - Your Radar public key for map functionality (defaults to test key if not set)

- `EMAIL_FROM` - Email address used as sender for outgoing emails (defaults to "info@ysc.org")
- `EMAIL_FROM_NAME` - Display name for outgoing emails (defaults to "YSC")
- `EMAIL_CONTACT` - General contact email address (defaults to "info@ysc.org")
- `EMAIL_ADMIN` - Admin email address (defaults to "admin@ysc.org")
- `EMAIL_MEMBERSHIP` - Membership-related email address (defaults to "membership@ysc.org")
- `EMAIL_BOARD` - Board email address (defaults to "board@ysc.org")
- `EMAIL_VOLUNTEER` - Volunteer email address (defaults to "volunteer@ysc.org")
- `EMAIL_TAHOE` - Tahoe cabin email address (defaults to "tahoe@ysc.org")
- `EMAIL_CLEAR_LAKE` - Clear Lake cabin email address (defaults to "clearlake@ysc.org")

### Setting Environment Variables

You can set these variables in one of two ways:

#### Option 1: Export in your shell

```bash
export STRIPE_SECRET="sk_test_..."
export STRIPE_PUBLIC_KEY="pk_test_..."
export STRIPE_WEBHOOK_SECRET="whsec_..."
export RADAR_PUBLIC_KEY="prj_live_pk_..."  # Optional, defaults to test key
```

#### Option 2: Create a `.env` file

Create a `.env` file in the project root:

```bash
STRIPE_SECRET=sk_test_...
STRIPE_PUBLIC_KEY=pk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...
RADAR_PUBLIC_KEY=prj_live_pk_...  # Optional, defaults to test key
```

**Note:** Exported environment variables take precedence over values in the `.env` file. The `make dev` command will automatically load variables from `.env` if the file exists.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

- Official website: https://www.phoenixframework.org/
- Guides: https://hexdocs.pm/phoenix/overview.html
- Docs: https://hexdocs.pm/phoenix
- Forum: https://elixirforum.com/c/phoenix-forum
- Source: https://github.com/phoenixframework/phoenix
