# Installing Rojo on Mac (Manual Method)

Since automatic installation isn't working, here's the manual approach:

## Step 1: Download Rojo Manually

1. Open this link in your browser: https://github.com/rojo-rbx/rojo/releases/latest
2. Look for the file named `rojo-X.X.X-macos.zip` (e.g., `rojo-7.6.1-macos.zip`)
3. Download it to your Downloads folder

## Step 2: Extract and Move the Binary

Open Terminal and run these commands:

```bash
# Navigate to Downloads
cd ~/Downloads

# Unzip the file (replace X.X.X with the actual version)
unzip rojo-*-macos.zip

# Create a local bin directory if it doesn't exist
mkdir -p ~/.local/bin

# Move rojo to your local bin
mv rojo ~/.local/bin/

# Make it executable
chmod +x ~/.local/bin/rojo
```

## Step 3: Remove macOS Quarantine Flag

macOS blocks downloaded executables by default. Remove the quarantine flag:

```bash
xattr -d com.apple.quarantine ~/.local/bin/rojo
```

If that doesn't work, try:
```bash
sudo xattr -rd com.apple.quarantine ~/.local/bin/rojo
```

## Step 4: Add to PATH

Add this line to your shell config file (`~/.zshrc` for zsh or `~/.bash_profile` for bash):

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Then reload your shell:
```bash
source ~/.zshrc  # or source ~/.bash_profile
```

## Step 5: Verify Installation

```bash
rojo --version
```

You should see the version number printed.

## Step 6: Start Rojo in Your Project

Navigate to your project directory and start Rojo:

```bash
cd /Users/sk/Movies/CapCut/lux-agentic-ai
rojo serve
```

## Step 7: Connect from Roblox Studio

1. Open Roblox Studio
2. Install the Rojo plugin from: https://www.roblox.com/library/13916111004/Rojo-7-4
3. Click the Rojo plugin button
4. Click "Connect" (it will connect to `localhost:34872`)

---

## Alternative: If You Still Get Security Errors

If macOS still blocks it:

1. Go to **System Settings** > **Privacy & Security**
2. Scroll down to see a message about "rojo" being blocked
3. Click **"Open Anyway"**
4. Try running `rojo --version` again
