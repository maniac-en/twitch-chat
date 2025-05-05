#!/usr/bin/env bash

# Configuration
CONFIG_DIR="$HOME/.config/twitch-chat"
ENV_FILE="$CONFIG_DIR/.twitch-chat-env"
VERBOSE=false
SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_NAME="$(basename "$0")"

# Create config directory if it doesn't exist
mkdir -p "$CONFIG_DIR"

# Function definitions
function log {
  if [ "$VERBOSE" = true ]; then
    echo "[$(date "+%H:%M:%S")] $1"
  fi
}

function error {
  echo "[ERROR] $1" >&2
}

function success {
  echo "[SUCCESS] $1"
}

function show_help {
  echo "Usage: twitch-chat [OPTIONS] MESSAGE"
  echo ""
  echo "Send a message to your Twitch chat from command line."
  echo ""
  echo "Options:"
  echo "  -h, --help      Show this help message"
  echo "  -v, --verbose   Verbose mode (detailed output)"
  echo "  --setup         Configure Twitch API credentials"
  echo "  --install       Install script globally"
  echo ""
  exit 0
}

function open_url {
  local url="$1"

  # Try different commands based on OS
  if command -v xdg-open &>/dev/null; then
    xdg-open "$url" &>/dev/null & # Linux
  elif command -v open &>/dev/null; then
    open "$url" # macOS
  elif command -v start &>/dev/null; then
    start "$url" # Windows with Git Bash
  else
    echo "Please open this URL in your browser:"
    echo "$url"
    return 1
  fi

  return 0
}

function setup_env {
  if [ -f "$ENV_FILE" ]; then
    echo "Existing configuration found!"
    echo "Setting up new credentials will overwrite your existing configuration."
    echo "Do you want to continue? (y/n)"
    read -r overwrite_choice

    if [[ ! "$overwrite_choice" =~ ^[Yy] ]]; then
      echo "Setup cancelled. Your existing configuration remains unchanged."
      exit 0
    fi
  fi

  echo "Setting up Twitch chat configuration..."
  read -p "Enter your Twitch username: " username
  read -p "Enter your client ID: " client_id
  read -p "Enter your client secret: " client_secret

  cat > "$ENV_FILE" << EOF
twitch_username=$username
client_id=$client_id
client_secret=$client_secret
EOF

  echo "Setup complete! Now run the script with a message to start the authorization process."
  exit 0
}

function install_script {
  local install_dir="$HOME/.local/bin"
  mkdir -p "$install_dir"
  cp "$SCRIPT_PATH" "$install_dir/twitch-chat"
  chmod +x "$install_dir/twitch-chat"

  echo "Installation complete! Script installed as 'twitch-chat'."
  echo ""

  # Check if ~/.local/bin is in PATH
  if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    echo "Please add the following line to your ~/.bashrc or ~/.zshrc:"
    echo 'export PATH="$HOME/.local/bin:$PATH"'
    echo ""
    echo "Then restart your terminal or run: source ~/.bashrc"
  fi

  exit 0
}

function extract_code_from_url {
  local url="$1"
  local code=$(echo "$url" | grep -o 'code=\([^&]*\)' | cut -d= -f2)
  echo "$code"
}

function guide_auth_flow {
  echo "You need to authorize your application with the required scopes."
  echo ""
  echo "Opening authorization URL in your default browser..."
  local auth_url="https://id.twitch.tv/oauth2/authorize?client_id=$client_id&redirect_uri=http://localhost&response_type=code&scope=user:write:chat+user:bot"

  if ! open_url "$auth_url"; then
    echo "Could not open browser automatically."
    echo "Please open this URL manually:"
    echo "$auth_url"
  fi

  echo ""
  echo "After authorizing, you'll be redirected to a URL like:"
  echo "   http://localhost/?code=AUTHORIZATION_CODE&scope=user%3Awrite%3Achat+user%3Abot"
  echo ""
  echo "Copy the ENTIRE redirect URL and paste it below:"
  echo -n "Enter the full redirect URL: "
  read redirect_url

  # Extract the authorization code from the URL
  auth_code=$(extract_code_from_url "$redirect_url")

  if [ -z "$auth_code" ]; then
    error "Could not extract authorization code from URL"
    exit 1
  fi

  log "Extracted code: $auth_code"
  log "Exchanging authorization code for access token..."

  response=$(curl -s -X POST "https://id.twitch.tv/oauth2/token" \
    -d "client_id=$client_id&client_secret=$client_secret&code=$auth_code&grant_type=authorization_code&redirect_uri=http://localhost")

  auth_token=$(echo "$response" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
  refresh_token=$(echo "$response" | grep -o '"refresh_token":"[^"]*' | cut -d'"' -f4)

  if [ -z "$auth_token" ]; then
    error "Failed to get auth token. Response: $response"
    exit 1
  fi

  log "Access token obtained successfully!"
  log "Refresh token saved for future use."

  # Update tokens in env file (without creating .bak files)
  local temp_file=$(mktemp)
  grep -v '^auth_token=' "$ENV_FILE" | grep -v '^refresh_token=' > "$temp_file"
  echo "auth_token=$auth_token" >> "$temp_file"
  echo "refresh_token=$refresh_token" >> "$temp_file"
  mv "$temp_file" "$ENV_FILE"
}

function refresh_auth_token {
  log "Refreshing auth token..."

  if [ -z "$refresh_token" ]; then
    log "No refresh token found. Need to perform full authorization."
    guide_auth_flow
    return
  fi

  response=$(curl -s -X POST "https://id.twitch.tv/oauth2/token" \
    -d "client_id=$client_id&client_secret=$client_secret&refresh_token=$refresh_token&grant_type=refresh_token")

  auth_token=$(echo "$response" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
  new_refresh_token=$(echo "$response" | grep -o '"refresh_token":"[^"]*' | cut -d'"' -f4)

  if [ -z "$auth_token" ]; then
    log "Failed to refresh token. Trying full authorization..."
    guide_auth_flow
    return
  fi

  # Update refresh token if provided
  if [ -n "$new_refresh_token" ]; then
    refresh_token=$new_refresh_token
  fi

  # Update tokens in env file (without creating .bak files)
  local temp_file=$(mktemp)
  grep -v '^auth_token=' "$ENV_FILE" | grep -v '^refresh_token=' > "$temp_file"
  echo "auth_token=$auth_token" >> "$temp_file"
  echo "refresh_token=$refresh_token" >> "$temp_file"
  mv "$temp_file" "$ENV_FILE"

  log "Token refreshed successfully"
}

function fetch_broadcaster_id {
  log "Fetching broadcaster ID..."
  broadcaster_id=$(curl -s -X GET "https://api.twitch.tv/helix/users" \
    -H "Authorization: Bearer $auth_token" \
    -H "Client-Id: $client_id" \
    | grep -o '"id":"[^"]*' | cut -d'"' -f4)

  if [ -z "$broadcaster_id" ]; then
    error "Failed to fetch Broadcaster ID, exiting..."
    exit 1
  fi

  log "Broadcaster ID obtained: $broadcaster_id"

  # Update broadcaster_id in env file (without creating .bak files)
  local temp_file=$(mktemp)
  grep -v '^broadcaster_id=' "$ENV_FILE" > "$temp_file"
  echo "broadcaster_id=$broadcaster_id" >> "$temp_file"
  mv "$temp_file" "$ENV_FILE"
}

function validate_token {
  log "Validating auth token..."
  validation=$(curl -s -X GET "https://id.twitch.tv/oauth2/validate" \
    -H "Authorization: Bearer $auth_token")

  error=$(echo "$validation" | grep -o '"status":[0-9]*' | cut -d':' -f2)

  if [ "$error" = "401" ] || [ -z "$(echo "$validation" | grep -o '"client_id"')" ]; then
    log "Auth token invalid, refreshing..."
    refresh_auth_token
    return 1
  fi

  # Check if we have the right scopes
  scopes=$(echo "$validation" | grep -o '"scopes":\[[^]]*\]' | grep -o 'user:write:chat')

  if [ -z "$scopes" ]; then
    log "Auth token lacks required scopes, reauthorizing..."
    guide_auth_flow
    return 1
  fi

  log "Auth token validated with proper scopes"
  return 0
}

function send_message {
  local message="$1"
  log "Sending message: $message"

  response_body=$(curl -s -X POST 'https://api.twitch.tv/helix/chat/messages' \
    -H "Authorization: Bearer $auth_token" \
    -H "Client-Id: $client_id" \
    -H 'Content-Type: application/json' \
    -d "{
      \"broadcaster_id\": \"$broadcaster_id\",
      \"sender_id\": \"$broadcaster_id\",
      \"message\": \"$message\"
    }" \
    -w "\n%{http_code}")

  http_code=$(echo "$response_body" | tail -n1)
  response_content=$(echo "$response_body" | sed '$d')

  log "HTTP Code: $http_code"
  log "Response: $response_content"

  if [ "$http_code" = "200" ] || [ "$http_code" = "204" ]; then
    success "Message sent successfully"
    return 0
  else
    error "Failed to send the message: $response_content"
    return 1
  fi
}

function check_first_run {
  # Check if script is installed in PATH
  if command -v twitch-chat >/dev/null 2>&1; then
    local installed_path=$(command -v twitch-chat)
    # Check if this is the installed version
    if [ "$installed_path" != "$SCRIPT_PATH" ]; then
      # Already installed, but not running the installed version
      return 0
    fi
  else
    # Not installed
    echo "It looks like this is your first time running this script."
    echo "Would you like to install it globally to run from anywhere? (y/n)"
    read -r install_choice
    if [[ "$install_choice" =~ ^[Yy] ]]; then
      install_script
    else
      echo "You can install later with: $SCRIPT_NAME --install"
    fi
  fi

  # Check if config file exists
  if [ ! -f "$ENV_FILE" ]; then
    echo "You need to set up your Twitch credentials."
    echo "Would you like to set them up now? (y/n)"
    read -r setup_choice
    if [[ "$setup_choice" =~ ^[Yy] ]]; then
      setup_env
    else
      echo "You can set up later with: $SCRIPT_NAME --setup"
      exit 1
    fi
  fi
}

# Process command line options
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_help
      ;;
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    --setup)
      setup_env
      ;;
    --install)
      install_script
      ;;
    *)
      break
      ;;
  esac
done

# Check if this is the first run and handle installation/setup
check_first_run

# Check if message was provided
if [ $# -eq 0 ]; then
  echo "No message provided!"
  echo ""
  echo "To send a message: twitch-chat [message]"
  echo "For help: twitch-chat --help"
  exit 1
fi

# Check if config exists
if [ ! -f "$ENV_FILE" ]; then
  error "Configuration file not found!"
  echo "Run 'twitch-chat --setup' to configure your Twitch credentials."
  exit 1
fi

# Load environment variables
source "$ENV_FILE"

# Check for required variables
if [ -z "$twitch_username" ] || [ -z "$client_id" ] || [ -z "$client_secret" ]; then
  error "Missing required configuration!"
  echo "Run 'twitch-chat --setup' to properly configure your Twitch credentials."
  exit 1
fi

# Check token validity
if [ -n "$auth_token" ]; then
  validate_token || true  # Ignore return value since the function will refresh if needed
else
  log "No auth token found, starting authorization..."
  guide_auth_flow
fi

# Check broadcaster ID
if [ -z "$broadcaster_id" ]; then
  fetch_broadcaster_id
fi

# Send the message
send_message "$*"
