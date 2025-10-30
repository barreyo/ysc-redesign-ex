# Ysc

To start your Phoenix server:

- Run `mix setup` to install and setup dependencies
- Set up environment variables (see Environment Variables section below)
- Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Environment Variables

This application requires the following environment variables to be set:

### Stripe Configuration

- `STRIPE_SECRET` - Your Stripe secret key
- `STRIPE_PUBLIC_KEY` - Your Stripe publishable key
- `STRIPE_WEBHOOK_SECRET` - Your Stripe webhook secret

You can get these from your [Stripe Dashboard](https://dashboard.stripe.com/apikeys).

### Setting Environment Variables

#### Option 1: Export in your shell

```bash
export STRIPE_SECRET="sk_test_..."
export STRIPE_PUBLIC_KEY="pk_test_..."
export STRIPE_WEBHOOK_SECRET="whsec_..."
```

#### Option 2: Create a .env file (if using a tool like dotenv)

Create a `.env` file in the project root:

```
STRIPE_SECRET=sk_test_...
STRIPE_PUBLIC_KEY=pk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...
```

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

- Official website: https://www.phoenixframework.org/
- Guides: https://hexdocs.pm/phoenix/overview.html
- Docs: https://hexdocs.pm/phoenix
- Forum: https://elixirforum.com/c/phoenix-forum
- Source: https://github.com/phoenixframework/phoenix
