# Twitch Chat CLI

A command-line tool for sending messages to your Twitch chat directly from your terminal.

## Features

- Send chat messages to your Twitch stream from your terminal
- Automatic authentication and token refresh
- Auto-discovery of broadcaster ID
- Easy installation and setup
- Minimal output by default, verbose mode available

## Prerequisites

- Bash shell
- curl
- A registered Twitch application (client ID and client secret)
    - Make sure it's redirect URL is `http://localhost`

## Installation

### Automatic Installation

Run the script once, and it will offer to install itself globally:

```bash
./twitch-chat.sh "Hello, World!"
```

Alternatively, use the install option:

```bash
./twitch-chat.sh --install
```

### Manual Installation

1. Copy the script to a directory in your PATH:

```bash
cp twitch-chat.sh ~/.local/bin/twitch-chat
chmod +x ~/.local/bin/twitch-chat
```

2. Make sure `~/.local/bin` is in your PATH:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

> Follow relevant steps for above as per your shell, say, `zsh`, `fish`, etc.

## Setup

### Twitch Application Setup

Before using this tool, you need to create a Twitch application:

1. Go to [Twitch Developer Console](https://dev.twitch.tv/console/apps)
2. Click "Register Your Application"
3. Fill in the required fields:
   - Name: Choose a name for your application
   - OAuth Redirect URLs: Add `http://localhost`
   - Category: Choose "Chat Bot"
4. Click "Create"
5. Copy your Client ID and generate a Client Secret

### Tool Configuration

Run the setup command:

```bash
twitch-chat --setup
```

You'll be prompted to enter:
- Your Twitch username
- Client ID
- Client Secret

## Usage

### Sending a Message

```bash
twitch-chat "Hello from my terminal!"
```

The first time you run the script, it will guide you through the authorization process.

### Command-line Options

```
Usage: twitch-chat [OPTIONS] MESSAGE

Send a message to your Twitch chat from command line.

Options:
  -h, --help      Show this help message
  -v, --verbose   Verbose mode (detailed output)
  --setup         Configure Twitch API credentials
  --install       Install script globally
```

## Authentication

The script handles authentication automatically:

1. First run: You'll be prompted to authorize your application
2. A browser window will open with the Twitch authorization page
3. After authorizing, copy the entire redirect URL back to the terminal
4. The script will extract the authorization code and get access and refresh tokens
5. Future runs: The script refreshes tokens automatically when needed

## Configuration

Your configuration is stored in:
```
~/.config/twitch-chat/.twitch-chat-env
```

## Troubleshooting

### Common Issues

1. **Authentication fails**: Check that your client ID and secret are correct
2. **Token refresh fails**: Try running with `--verbose` flag for more details
3. **Browser doesn't open**: Copy and paste the URL manually

### Getting More Information

Use the verbose flag to see detailed logs:

```bash
twitch-chat -v "Testing with verbose output"
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- [Twitch API Documentation](https://dev.twitch.tv/docs/api/)
- [Twitch Chat Documentation](https://dev.twitch.tv/docs/api/reference/#send-chat-message)
