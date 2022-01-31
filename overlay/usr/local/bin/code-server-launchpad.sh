#!/usr/bin/dumb-init /bin/bash
# shellcheck shell=bash

# Instead of using code-server's main entrypoint script, we'll bring stuff from there
# into here.
set -e

if [[ $1 == "shell" ]]; then
  exec bash -l
fi

START_DIR="${START_DIR:-/workspace/home}"
PREFIX=${TEMPLATE_SLUG_PREFIX}

if [[ ! -d $START_DIR ]]; then
   mkdir -p "$START_DIR"
fi

# We do this first to ensure sudo works below when renaming the user.
# Otherwise the current container UID may not exist in the passwd database.
eval "$(fixuid -q)"

if [ "${DOCKER_USER-}" ]; then
  echo "[$PREFIX] Fixing possible uid/gid mismatches..."
  USER="$DOCKER_USER"
  if [ "$DOCKER_USER" != "$(whoami)" ]; then
    echo "$DOCKER_USER ALL=(ALL) NOPASSWD:ALL" | sudo tee -a /etc/sudoers.d/nopasswd > /dev/null
    # Unfortunately we cannot change $HOME as we cannot move any bind mounts
    # nor can we bind mount $HOME into a new home as that requires a privileged container.
    sudo usermod --login "$DOCKER_USER" coder
    sudo groupmod -n "$DOCKER_USER" coder

    sudo sed -i "/coder/d" /etc/sudoers.d/nopasswd
  fi
fi

useDefaultConfig() {
       git config  --global user.name "Recap Time Bot"
       git config --global user.email "rtappbot-noreply@madebythepins.tk"
}


if [[ $GIT_USER_EMAIL == "" ]] && [[ $GIT_USER_NAME == "" ]]; then
  echo "[$PREFIX] No email address and name found for configuring Git. Git will prompt you to configure them"
  echo "[$PREFIX] before ever commiting something. Falling back to defaults using github:RecapTimeBot user info..."
  useDefaultConfig
elif [[ $GIT_USER_EMAIL == "" ]]; then
  echo "[$PREFIX] Git user email found, but name isn't found. Using defaults based on"
  echo "[$PREFIX] github:RecapTimeBot user info..."
  useDefaultConfig
elif [[ $GIT_USER_NAME == "" ]]; then
  echo "[$PREFIX] Git user name found, but email isn't found. Using defaults based on"
  echo "[$PREFIX] github:RecapTimeBot user info..."
  useDefaultConfig
else
  git config --global user.name "$GIT_USER_NAME"
  git config --global user.email "$GIT_USER_EMAIL"
fi

# handle auth token saving to gitconfig stuff here
### GITHUB / GHE ###
if [[ $GITHUB_TOKEN != "" ]]; then
  echo "[$PREFIX] Setting up auth for GitHub"
  printf "machine github.com\nlogin $GITHUB_LOGIN\npassword $GITHUB_TOKEN\n" > ~/.netrc
elif [[ $GITHUB_TOKEN != "" ]] && [[ $GHE_HOST != "" ]]; then
  echo "[$PREFIX] GHE user detected, setting up config..."
  printf "machine $GHE_HOST\nlogin $GITHUB_LOGIN\npassword $GITHUB_TOKEN\n" > ~/.netrc
else
  echo "[$PREFIX] No GitHub.com access token found. You may need to manually copy your PATs from"
  echo "[$PREFIX] your password manager or generate one if you have. Implementing SSH storage is still an"
  echo "[$PREFIX] work-in-progress thing for now. See https://cdrs-docs.rtapp.tk/setup-gh-pat for details."
  echo "[$PREFIX] Atleast repo (for private repos) or public_repo (for public repos). Alternatively, use"
  echo "[$PREFIX] the GitHub CLI to authenicate against Git CLI."
fi
### GITLAB SAAS (gitlab.com) ###
if [[ $GITLAB_TOKEN != "" ]] && [[ $GITLAB_LOGIN != "" ]]; then
  echo "[$PREFIX] Setting up auth for GitLab SaaS"
  echo >> ~/.netrc
  # shellcheck disable=SC2059
  printf "machine gitlab.com\nlogin $GITLAB_LOGIN\npassword $GITLAB_TOKEN\n" >> ~/.netrc
elif [[ $GITLAB_TOKEN != "" ]] && [[ $GITLAB_LOGIN == "" ]] && [[ $GITLAB_HOST != "" ]]; then
  echo "[$PREFIX] Setting up auth for GitLab self-hosted"
  # shellcheck disable=SC2059
  echo >> ~/.netrc
  printf "machine $GITLAB_HOST\nlogin $GITLAB_LOGIN\npassword $GITLAB_TOKEN\n" >> ~/.netrc
else
  echo "[$PREFIX] No GitLab SaaS access token found. You may need to manually copy your PATs from your"
  echo "[$PREFIX] password manager or generate one if you have. Implementing SSH storage is still an"
  echo "[$PREFIX] work-in-progress thing for now. See https://cdrs-docs.rtapp.tk/setup-gh-pat for details."
  echo "[$PREFIX] Alternatively, use GLab CLI to authenicate against the Git CLI."
fi

# function to clone the git repo or add a user's first file if no repo was specified.
project_init () {
    if [[ -d "$START_DIR/.git" ]]; then
      echo "[$PREFIX] Fetching updates from remotes..."
      git fetch --all
    else
      [ -z "${GIT_REPO}" ] && echo "[$PREFIX] No GIT_REPO specified" && echo "Example file. Have questions? Join us at https://community.coder.com" > $START_DIR/coder.txt || git clone $GIT_REPO $START_DIR
    fi
}

generatePassword() {
  OPENSSL_GENERATED_PASSWORD=$(openssl rand -base64 32)
  if [[ $GENERATE_PASSWORD == "true" ]] && [[ $PASSWORD != "" ]]; then
     echo "[$PREFIX] Your Web IDE secret is: $PASSWORD"
     echo "[$PREFIX] Keep this secret as long as possible. If sharing devenvs with someone,use secure channels and don't leak it anyway."
  elif [[ $GENERATE_PASSWORD == "true" ]] || [[ $PASSWORD == "" ]]; then
     export PASSWORD=$OPENSSL_GENERATED_PASSWORD
     echo "[$PREFIX] Your Web IDE password is: $PASSWORD"
     echo "[$PREFIX] Use this to securely log you into your web IDE. To permanently set PASSWORD into that,"
     echo "[$PREFIX] set GENERATE_PASSWORD to false and set PASSWORD to it in your PaaS service/Docker Compose config file."
  else
     echo "[$PREFIX] Your Web IDE secret is: $PASSWORD"
     echo "[$PREFIX] Keep this secret as long as possible. If sharing devenvs with someone, use secure channels and don't leak it anyway."
  fi
}

# add rclone config and start rclone, if supplied
if [[ -z "${RCLONE_DATA}" ]]; then
    echo "[$PREFIX] RCLONE_DATA is not specified. Files will not persist"

    # start the project
    project_init

else
    echo "[$PREFIX] Copying rclone config..."
    mkdir -p /home/coder/.config/rclone/
    touch /home/coder/.config/rclone/rclone.conf
    echo "$RCLONE_DATA" | base64 -d > /home/coder/.config/rclone/rclone.conf

    # defasult to true
    RCLONE_VSCODE_TASKS="${RCLONE_VSCODE_TASKS:-true}"
    RCLONE_AUTO_PUSH="${RCLONE_AUTO_PUSH:-true}"
    RCLONE_AUTO_PULL="${RCLONE_AUTO_PULL:-true}"

    if [ "$RCLONE_VSCODE_TASKS" = "true" ]; then
        # install the extension to add to menu bar
        code-server --install-extension actboy168.tasks&
    else
        # user specified they don't want to apply the tasks
        echo "[$PREFIX] Skipping VS Code tasks for rclone"
    fi

    # Full path to the remote filesystem
    RCLONE_REMOTE_PATH=${RCLONE_REMOTE_NAME:-code-server-remote}:${RCLONE_DESTINATION:-code-server-files}
    RCLONE_SOURCE_PATH=${RCLONE_SOURCE:-$START_DIR}
    echo "rclone sync $RCLONE_SOURCE_PATH $RCLONE_REMOTE_PATH $RCLONE_FLAGS -vv" > /home/coder/.local/bin/rclone-push
    echo "rclone sync $RCLONE_REMOTE_PATH $RCLONE_SOURCE_PATH $RCLONE_FLAGS -vv" > /home/coder/.local/bin/rclone-pull
    chmod +x "$HOME"/.local/bin/push_remote.sh "$HOME"/.local/bin/pull_remote.sh
    ln -s "$HOME"/.local/bin/rclone-{pull,push} "$HOME"/{pull,push}_remote.sh

    if rclone ls "$RCLONE_REMOTE_PATH"; then

        if [ $RCLONE_AUTO_PULL = "true" ]; then
            # grab the files from the remote instead of running project_init()
            echo "[$PREFIX] Pulling existing files from remote..."
            /home/coder/pull_remote.sh&
        else
            # user specified they don't want to apply the tasks
            echo "[$PREFIX] Auto-pull is disabled"
        fi

    else

        if [ "$RCLONE_AUTO_PUSH" = "true" ]; then
            # we need to clone the git repo and sync
            echo "[$PREFIX] Pushing initial files to remote..."
            project_init
            /home/coder/push_remote.sh&
        else
            # user specified they don't want to apply the tasks
            echo "[$PREFIX] Auto-push is disabled"
        fi

    fi

fi

echo "[$PREFIX] Updating package list caches..."
sudo apt update

echo
generatePassword
echo

echo "[$PREFIX] Attempting to connect to tailnet..."
if [[ $SKIP_TAILSCALED_STARTUP == "" ]] && [[ "$(command -v tailscaled)" != "" ]]; then
  tailscaled --tun=userspace-networking --socks5-server=localhost:1055 &
fi

if [[ $1 == "" ]] || [[ $1 == "start" ]]; then
  echo "[$PREFIX] Starting code-server..."
  exec /usr/bin/code-server --bind-addr 0.0.0.0:8080 "$START_DIR"
fi
