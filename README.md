# A pure Shell script for startssl free certificate
- Written purely in Shell (Unix shell) language.
- Fully startapi implementation.
- Support unlimited Class 1 free certificate from StartSSL.
- Support unlimited Class 2 and wildcard certificate from StartSSL( Coming soon ).
- Simple, powerful and very easy to use. You only need 3 minutes to learn.
- Bash, dash and sh compatible. 
- Simplest shell script for startssl free certificate client.
- Purely written in Shell with no dependencies on python or go.
- Just one script, to issue, renew and install your certificates automatically.
- DOES NOT require `root/sudoer` access.

It's probably the `easiest&smallest&smartest` shell script to automatically issue & renew the free certificates from StartSSL.com.


Wiki: https://github.com/Neilpang/startapi.sh/wiki



# Supported Mode

1. Webroot mode
1. Standalone mode
1. Email mode (coming soon)


# How to install

### 1. Install online:

Check this project: https://github.com/Neilpang/get.startapi.sh

```bash
curl https://get.startapi.sh | sh

```

Or:

```bash
wget -O -  https://get.startapi.sh | sh

```


### 2. Or, Install from git:

Clone this project: 

```bash
git clone https://github.com/Neilpang/startapi.sh.git
cd ./startapi.sh
./startapi.sh --install
```

You `don't have to be root` then, although `it is recommended`.

Advanced Installation:  https://github.com/Neilpang/startapi.sh/wiki/How-to-install

The installer will perform 3 actions:

1. Create and copy `startapi.sh` to your home dir (`$HOME`):  `~/.startapi.sh/`.
All certs will be placed in this folder.
2. Create alias for: `startapi.sh=~/.startapi.sh/startapi.sh`. 
3. Create everyday cron job to check and renew the cert if needed.

Cron entry example:

```bash
0 0 * * * "/home/user/.startapi.sh"/startapi.sh --cron --home "/home/user/.startapi.sh" > /dev/null
```

After the installation, you must close current terminal and reopen again to make the alias take effect.

Show help message:

```

root@v1:~# startapi.sh -h

```

# Create your StartSSL.com account and get your api key and api token:

Before you can issue cert, you must register an account at startssl.com and get the api key and api token:

https://github.com/Neilpang/startapi.sh/wiki/Create-startssl-api-token-and-api-key

```
startapi.sh --setAPIKey  api.p12  --password xxxxxxxxxx
startapi.sh --setAPIToken  "tk_xxxxxxxxxxxxxx"
```

OK, you are ready to issue cert now.


# Just issue a cert:

**Example 1:** Single domain.

```bash
startapi.sh --issue -d aa.com -w /home/wwwroot/aa.com
```

**Example 2:** Multiple domains in the same cert.

```bash
startapi.sh --issue -d aa.com -d www.aa.com -d cp.aa.com -w /home/wwwroot/aa.com 
```

The parameter `/home/wwwroot/aa.com` is the web root folder. You **MUST** have `write access` to this folder.

Second argument **"aa.com"** is the main domain you want to issue cert for.
You must have at least a domain there.

You must point and bind all the domains to the same webroot dir: `/home/wwwroot/aa.com`.

Generate/issued certs will be placed in `~/.startapi.sh/aa.com/`

The issued cert will be renewed every 300 days automatically.

More examples: https://github.com/Neilpang/startapi.sh/wiki/How-to-issue-a-cert


# Install issued cert to apache/nginx etc.

After you issue a cert, you probably want to install the cert with your nginx/apache or other servers you may be using.

```bash
startapi.sh --installcert -d aa.com \
--certpath /path/to/certfile/in/apache/nginx  \
--keypath  /path/to/keyfile/in/apache/nginx  \
--capath   /path/to/ca/certfile/apache/nginx   \
--fullchainpath path/to/fullchain/certfile/apache/nginx \
--reloadcmd  "service apache2|nginx reload"
```

Only the domain is required, all the other parameters are optional.

Install the issued cert/key to the production apache or nginx path.

The cert will be `renewed every 300 days by default` (which is configurable). Once the cert is renewed, the apache/nginx will be automatically reloaded by the command: `service apache2 reload` or `service nginx reload`.

# Use Standalone server to issue cert

**(requires you be root/sudoer, or you have permission to listen tcp 80 port)**

The tcp `80` port **MUST** be free to listen, otherwise you will be prompted to free the `80` port and try again.

```bash
startapi.sh --issue --standalone -d aa.com -d www.aa.com -d cp.aa.com
```

More examples: https://github.com/Neilpang/startapi.sh/wiki/How-to-issue-a-cert


# Use email mode

(Coming soon)

# Issue ECC certificate:

Just set the `length` parameter with a prefix `ec-`.

For example:

### Single domain ECC cerfiticate:

```bash
startapi.sh --issue -w /home/wwwroot/aa.com -d aa.com --keylength  ec-256
```

SAN multi domain ECC certificate:

```bash
startapi.sh --issue -w /home/wwwroot/aa.com -d aa.com -d www.aa.com --keylength  ec-256
```

Please look at the last parameter above.

Valid values are:

1. **ec-256 (prime256v1, "ECDSA P-256")**
2. **ec-384 (secp384r1,  "ECDSA P-384")**
3. **ec-521 (secp521r1,  "ECDSA P-521")**


# Issue Class 2 IV
You must pay to startssl.com to pass the Class 2 IV validation,  then you can issue IV certificate:
Just add `--iv` parameter.
```
startapi.sh  --issue -d ....  -w ...   --iv
```

# Issue Wildcard certificate:
You must pay to startssl.com to pass the Class 2 IV validation,  then you can issue Wildcard IV certificate:

```
startapi.sh  --issue  -d "aa.com"  -d "*.aa.com"  -w /home/wwwroot/aa.com   --iv
```



# Acknowledgment
1. StartSSL.com: https://www.startssl.com
2. StartAPI: https://startssl.com/StartAPI
3. acme.sh: https://acme.sh

# License & Other

License is GPLv3

Please Star and Fork me.

[Issues](https://github.com/Neilpang/startapi.sh/issues) and [pull requests](https://github.com/Neilpang/startapi.sh/pulls) are welcomed.



