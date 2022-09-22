# NERSC SSH Utilities

![Demo](demo.gif)

This is a wrapper for NERSC's [sshproxy](https://docs.nersc.gov/connect/mfa/#sshproxy) utility. It is aimed for *nix systems, but was only tested on MacOS.

There are two options to log into NERSC resources (Cori, Perlmutter, etc.):
1. Enter your password + OTP every single time you log in.
2. Use the [sshproxy](https://docs.nersc.gov/connect/mfa/#sshproxy) script, you only have to enter your credentials once every 24 hours.

However, I found it a little annoying to run:

```
./sshproxy.sh -u <user> [other flags]
# Enter credentials
ssh <user>@<resource>.nersc.gov
```

## Usage

```
Usage: nersc_ssh.sh [flags]

	 -u, --user <username>			    NERSC username
						                (default: ${USER})
	 -c, --cluster <cluster>		    NERSC Cluster (Perlmutter or Cori)
						                (default: perlmutter)
	 -o, --cert <certname>			    Filename for private key
						                (default: nersc)
	 -s, --sshproxy <sshproxy>		    Absolute path for sshproxy.sh script
						                (default: /path/to/NERSC-SSH-1Password/sshproxy.sh)
	     --onepass <1password_entry>	Name of the 1password entry with NERSC credentials
	 -p, --putty				        Get keys in PuTTY compatible (ppk) format.
                                        (This flag is sort of pointless since this is a *nix script)
	 -h, --help 				        Print this usage message and exit
```


## One-command connection
Due to my laziness, I wrote this script so I can just add this line to my `.zshrc`/`.bashrc`/etc.

```
alias cori="./nersc_ssh.sh -u <user> -c cori [other flags sshproxy flags, most are supported]
alias pm="./nersc_ssh.sh -u <user> -c perlmutter [other flags sshproxy flags, most are supported]
```

and run

```
cori # or pm
```
to automatically connect to Cori or Perlmutter. It automatically checks if a valid certificate is present, and if not, runs `sshproxy.sh` which prompts you for your credentials and then automatically shells into the requested resource.

Unfortunately, there is no real way around entering your credentials every 24 hours due to NERSC's policies (which are extremely reasonable, most clusters don't even offer the sshproxy service).

## 1Password Integration

However, I was even lazier than that, 10 seconds every day entering credentials is way too much for me. I use 1Password as my password manager so I decided to integrate it with sshproxy. This is still secure and shouldn't violate NERSC policies, it's no different than copying your password and OTP from 1Password by hand and pasting them in (technically it's more secure, I don't like having plaintext passwords in my clipboard).

This script integrates with 1Password via its command line interface ([CLI 2](https://developer.1password.com/docs/cli/get-started/), specifically, which requires 1Password 8).

> DISCLAIMER: I am emphatically *not* a security expert. I have done everything I can to make sure this script is as safe as possible, but you should use caution and use it at your own risk.

### 1Password CLI Setup
The setup is quite easy. See the link above for more details. First, you install the CLI via, e.g.,

```
brew install --cask 1password/tap/1password-cli
```

This works on Macs assuming you have [Homebrew](https://brew.sh). Installation instructions for other systems are available [here](https://developer.1password.com/docs/cli/get-started/#install), but I haven't tested this setup on Linux (pull requests are welcome if something goes awry). This script won't work with Windows Powershell, and I have no idea if it will work within WSL.

Optionally, you can turn on Biometric/Apple Watch unlock for the CLI, see [here](https://developer.1password.com/docs/cli/get-started/#turn-on-biometric-unlock). This is optional but it obviously makes your life easier.

Next, sign into your account, instructions are [here](https://developer.1password.com/docs/cli/get-started/#sign-in-to-your-account), but as a quick summary:

```
op vault ls
# Select your account
```

This is pretty much it. You can check if things work like this:

```
op item get <name> --field username
```

where `<name>` is the name of an entry in your 1Password database (e.g., your NERSC login entry). This should print the username. You can also use

```
op item get <name> --field password # Prints your password
op item get <name> --otp # Prints your OTP token

```
to print your password and OTP, but I don't recommend exposing your secrets in plain text in your terminal. *Technically* it's fine, but for example, iTerm2 had a [bug](https://www.bleepingcomputer.com/news/security/iterm2-leaks-everything-you-hover-in-your-terminal-via-dns-requests/) in 2017 that lead to passwords from the terminal leaking over DNS in plain text (it has since been fixed of course). You never know what's going on.

### Connecting to a cluster with 1Password

Now to connect to a cluster, you can simply use:
```
./path/to/repo/NERSC_SSH_Utils/nersc_ssh.sh -u <NERSC username> -c <cori or perlmutter> --onepass <NERSC credentials entry in 1Password> [other flags if necessary]
```

You should end up with `stdout` like this (see the demo GIF at the start of this `README`). I added some comments explaining the default values.

```
NERSC username: <username> # Defaults to ${USER}
Cluster: <cluster> # Defaults to perlmutter, cori is getting retired
Certificate name: nersc # Default
sshproxy: sshproxy.sh # Default path, relative to nersc_ssh.sh script
putty: False # Defaults to Fasle, not sure there's a point of this for a *nix target
1password entry: NERSC # Empty by default, won't use 1P without --onepass flag
Certificate file not found.
------------------------------------------
Generating new certificate.
1Password mode detected, retrieving credentials. # Prompt on AppleWatch/TouchID/etc.
SSH Proxy: 1Password credentials passed.
Successfully obtained ssh key /Users/ashour/.ssh/nersc
Key ${HOME}/.ssh/nersc is valid: from 2022-09-22T13:49:00 to 2022-09-23T13:50:23
New Certificate Generated
Proceeding with connection.
------------------------------------------
# Connected to cluster as usual.
```

To turn this into a one command afair, add the following to your `.zshrc`/`.bashrc`/etc.

```
alias cori='/path/to/NERSC-SSH-1Password/nersc_ssh.sh -u <user> -c cori --onepass <entry name>'
alias pm='/path/to/NERSC-SSH-1Password/nersc_ssh.sh -u <user> -c pm --onepass <entry name>'
```

## Implementation Details

The `nersc_ssh.sh` script is quite simple, most of the code really just handles the input and makes sure nothing is amiss. It then checks if a certificate is present and, if it is, checks its validity. If it has less than 5 minutes left, it will generate a new one before attempting to `ssh` into the cluster.

However, the 1Password integration required a slight modification to `sshproxy.sh` to pass the password and OTP automatically (via the `-w` flag).These are retrieved by `nersc_ssh.sh` from 1Password if the `--onepass <name>` flag is passed. If it's not, the script reverts to manual entry (default `sshproxy.sh` behavior). According to the license (at `/global/cfs/cdirs/mfa/NERSC-MFA/LICENSE.md` on NERSC's community file system), modifications to `sshproxy.sh` are allowed. 

If you don't want to use 1Password, you can just replace the `sshproxy.sh` file from this repo with the default one supplied by NERSC for peace of mind. You can see the differences between my file and NERSC's original file here [commit](link to commit).

## Potential Improvements and Extra Security
Under normal circumstances, the cleanest way to use the 1Password CLI for an application like this is via `.env` files and `op run` (see [here](https://developer.1password.com/docs/cli/secrets-environment-variables#use-environment-env-files). For example:

```nersc.env
NERSC_PASS="op://myvault/entry/section/password_entry_id"
NERSC_OPT="op://myvault/entry/section/otp_entry_id"
# You can get the IDs via `op item get <entry name> --format json
```

then

```
op run --env-file="nersc.env" -- cmd
```

When `cmd` is run, the secret references are replaced by the actual secrets. Unfortunately, the 1Password CLI 2 does not currently support extracting the actual OTP value via `.env` files, so this won't work. I will update the script to use this approach as soon as access to OTP is implemented.
