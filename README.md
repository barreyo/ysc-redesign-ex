# Ysc

## Getting Started

### Prerequisites

- Elixir and Erlang installed
- Docker and Docker Compose installed
- Stripe API keys (see Environment Variables section below)
- Fly.io CLI (optional, for sandbox deployment)

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

## Development Workflow

### Local Development

The development server runs with hot-reloading enabled. Changes to Elixir files will automatically reload the application.

### Testing QuickBooks Integration

To test QuickBooks integration locally, you'll need to configure QuickBooks sandbox credentials:

1. **Get QuickBooks Sandbox Credentials**:

   - Sign up for a [QuickBooks Developer Account](https://developer.intuit.com/)
   - Create a sandbox company in the QuickBooks Developer Dashboard
   - Create an app and obtain OAuth credentials

2. **Set QuickBooks Environment Variables**:

   Add these to your `.env` file or export them:

   ```bash
   # QuickBooks Sandbox Configuration
   QUICKBOOKS_CLIENT_ID=your_client_id
   QUICKBOOKS_CLIENT_SECRET=your_client_secret
   QUICKBOOKS_COMPANY_ID=your_company_id
   QUICKBOOKS_ACCESS_TOKEN=your_access_token
   QUICKBOOKS_REFRESH_TOKEN=your_refresh_token
   QUICKBOOKS_REALM_ID=your_realm_id
   QUICKBOOKS_APP_ID=your_app_id
   QUICKBOOKS_BASE_URL=https://sandbox-quickbooks.api.intuit.com/v3

   # QuickBooks Account IDs (required - get these from your sandbox company)
   QUICKBOOKS_BANK_ACCOUNT_ID=35
   QUICKBOOKS_STRIPE_ACCOUNT_ID=1150040000

   # QuickBooks Item IDs (optional - will auto-create if not set)
   QUICKBOOKS_EVENT_ITEM_ID=optional_item_id
   QUICKBOOKS_DONATION_ITEM_ID=optional_item_id
   QUICKBOOKS_TAHOE_BOOKING_ITEM_ID=optional_item_id
   QUICKBOOKS_CLEAR_LAKE_BOOKING_ITEM_ID=optional_item_id
   QUICKBOOKS_MEMBERSHIP_ITEM_ID=optional_item_id
   ```

3. **Test QuickBooks Sync**:
   - Create a payment, refund, or payout in the application
   - The system will automatically enqueue a QuickBooks sync job via Oban
   - Check the Oban dashboard at `/admin/settings` to monitor sync jobs
   - Verify the sync in your QuickBooks sandbox company

**Note:** QuickBooks sync jobs run asynchronously via Oban. You can monitor job status in the admin settings page.

### Useful Make Targets

The project includes several useful make targets for development:

#### Code Quality

- **`make format`** - Format all Elixir code using the project's formatter
- **`make lint`** - Run the full lint suite:
  - Runs Credo for code analysis
  - Checks that all files are properly formatted
  - Use this before committing code

#### Testing

- **`make test`** or **`make tests`** - Run the full test suite
  - Automatically starts PostgreSQL if needed
  - Runs all tests with trace output
- **`make test-failed`** - Run only tests that failed in the previous test run
  - Useful for iterating on failing tests

#### Database Management

- **`make reset-db`** - Drop the local development database
- **`make setup-dev-db`** - Create, migrate, and seed the local development database
  - Useful for resetting your local database to a clean state

#### Development Tools

- **`make shell`** - Open an IEx (Interactive Elixir) shell with the application loaded
  - Useful for debugging and exploring the codebase interactively
- **`make clean`** - Clean up Docker containers, volumes, and Elixir build artifacts
  - Use when you need a fresh start

#### Deployment

- **`make deploy-sandbox`** - Deploy the application to the Fly.io sandbox environment
  - Requires Fly.io CLI and authentication

#### Getting Help

- **`make help`** - Display all available make targets with descriptions

### Sandbox Environment (Fly.io)

The project includes a sandbox environment deployed on Fly.io for testing integrations in a production-like environment.

#### Sandbox Configuration

- **URL**: https://ysc-sandbox.fly.dev
- **Environment**: Sandbox (auto-shuts down after 10 minutes of inactivity)
- **QuickBooks**: Uses QuickBooks Sandbox API
- **Stripe**: Uses Stripe test mode

#### Sandbox Environment Variables

The sandbox is pre-configured with the following (see `etc/fly/fly-sandbox.toml`):

- QuickBooks Sandbox API endpoint
- Pre-configured QuickBooks account and item IDs
- Test Stripe price IDs
- Sandbox-specific email addresses (all emails use `+sandbox@ysc.org` suffix)

#### Deploying to Sandbox

To deploy changes to the sandbox environment:

```bash
make deploy-sandbox
```

Or manually:

```bash
fly deploy --dockerfile etc/docker/Dockerfile -a ysc-sandbox -c etc/fly/fly-sandbox.toml
```

**Note:** The sandbox environment automatically shuts down after 10 minutes of inactivity to save resources. It will automatically start when accessed.

#### Accessing Sandbox

1. Visit https://ysc-sandbox.fly.dev
2. The first request may take a moment as the app starts up
3. Use test credentials to log in (check with your team for sandbox credentials)

#### Sandbox Features

- Full application functionality in a production-like environment
- QuickBooks Sandbox integration (test transactions only)
- Stripe test mode (no real charges)
- Auto-shutdown to save resources
- Separate database from production

## Environment Variables

**Important:** All Stripe environment variables must be set before running `make dev`. You can either export them in your shell or use a `.env` file.

### Required Stripe Configuration

- `STRIPE_SECRET` - Your Stripe secret key
- `STRIPE_PUBLIC_KEY` - Your Stripe publishable key
- `STRIPE_WEBHOOK_SECRET` - Your Stripe webhook secret

You can get these from your [Stripe Dashboard](https://dashboard.stripe.com/apikeys).

### QuickBooks Configuration (Optional, for testing QuickBooks integration)

- `QUICKBOOKS_CLIENT_ID` - QuickBooks OAuth client ID
- `QUICKBOOKS_CLIENT_SECRET` - QuickBooks OAuth client secret
- `QUICKBOOKS_COMPANY_ID` - QuickBooks company ID
- `QUICKBOOKS_ACCESS_TOKEN` - OAuth access token
- `QUICKBOOKS_REFRESH_TOKEN` - OAuth refresh token
- `QUICKBOOKS_REALM_ID` - QuickBooks realm ID
- `QUICKBOOKS_APP_ID` - QuickBooks app ID
- `QUICKBOOKS_BASE_URL` - QuickBooks API base URL (defaults to sandbox: `https://sandbox-quickbooks.api.intuit.com/v3`)
- `QUICKBOOKS_BANK_ACCOUNT_ID` - QuickBooks bank account ID (required)
- `QUICKBOOKS_STRIPE_ACCOUNT_ID` - QuickBooks Stripe account ID (required)
- `QUICKBOOKS_EVENT_ITEM_ID` - QuickBooks event item ID (optional, auto-created if not set)
- `QUICKBOOKS_DONATION_ITEM_ID` - QuickBooks donation item ID (optional)
- `QUICKBOOKS_TAHOE_BOOKING_ITEM_ID` - QuickBooks Tahoe booking item ID (optional)
- `QUICKBOOKS_CLEAR_LAKE_BOOKING_ITEM_ID` - QuickBooks Clear Lake booking item ID (optional)
- `QUICKBOOKS_MEMBERSHIP_ITEM_ID` - QuickBooks membership item ID (optional)

**Note:** For local development, use QuickBooks Sandbox credentials. The sandbox environment on Fly.io is pre-configured with these values.

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
- `EMAIL_CLEAR_LAKE` - Clear Lake cabin email address (defaults to "cl@ysc.org.org")

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
# Stripe (Required)
STRIPE_SECRET=sk_test_...
STRIPE_PUBLIC_KEY=pk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...

# QuickBooks (Optional, for testing QuickBooks integration)
QUICKBOOKS_CLIENT_ID=your_client_id
QUICKBOOKS_CLIENT_SECRET=your_client_secret
QUICKBOOKS_COMPANY_ID=your_company_id
QUICKBOOKS_ACCESS_TOKEN=your_access_token
QUICKBOOKS_REFRESH_TOKEN=your_refresh_token
QUICKBOOKS_REALM_ID=your_realm_id
QUICKBOOKS_APP_ID=your_app_id
QUICKBOOKS_BASE_URL=https://sandbox-quickbooks.api.intuit.com/v3
QUICKBOOKS_BANK_ACCOUNT_ID=35
QUICKBOOKS_STRIPE_ACCOUNT_ID=1150040000

# Optional
RADAR_PUBLIC_KEY=prj_live_pk_...  # Optional, defaults to test key
```

**Note:** Exported environment variables take precedence over values in the `.env` file. The `make dev` command will automatically load variables from `.env` if the file exists.

**Security Note:** Never commit your `.env` file to version control. It's already included in `.gitignore`.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

- Official website: https://www.phoenixframework.org/
- Guides: https://hexdocs.pm/phoenix/overview.html
- Docs: https://hexdocs.pm/phoenix
- Forum: https://elixirforum.com/c/phoenix-forum
- Source: https://github.com/phoenixframework/phoenix
