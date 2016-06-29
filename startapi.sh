#!/usr/bin/env sh

VER=0.0.1

PROJECT_NAME="startapi.sh"

PROJECT_ENTRY="startapi.sh"

PROJECT="https://github.com/Neilpang/$PROJECT_NAME"

DEFAULT_CA="https://api.startssl.com"
STAGE_CA="https://apitest.startssl.com"


DEFAULT_USER_AGENT="$PROJECT_ENTRY client: $PROJECT"

VTYPE_HTTP="http"
VTYPE_EMAIL="email"
TOKEN_OK="ok"

MAX_RENEW=300

RENEW_SKIP=2


_URGLY_PRINTF=""
if [ "$(printf '\x41')" != 'A' ] ; then
  _URGLY_PRINTF=1
fi


_info() {
  if [ -z "$2" ] ; then
    echo "[$(date)] $1"
  else
    echo "[$(date)] $1='$2'"
  fi
}

_err() {
  _info "$@" >&2
  return 1
}

_debug() {
  if [ -z "$DEBUG" ] ; then
    return
  fi
  _err "$@"
  return 0
}

_debug2() {
  if [ "$DEBUG" ] && [ "$DEBUG" -ge "2" ] ; then
    _debug "$@"
  fi
  return
}

_startswith(){
  _str="$1"
  _sub="$2"
  echo "$_str" | grep "^$_sub" >/dev/null 2>&1
}

_endswith(){
  _str="$1"
  _sub="$2"
  echo "$_str" | grep "$_sub\$" >/dev/null 2>&1
}

_contains(){
  _str="$1"
  _sub="$2"
  echo "$_str" | grep "$_sub" >/dev/null 2>&1
}

_hasfield() {
  _str="$1"
  _field="$2"
  _sep="$3"
  if [ -z "$_field" ] ; then
    _err "Usage: str field  [sep]"
    return 1
  fi
  
  if [ -z "$_sep" ] ; then
    _sep=","
  fi
  
  for f in $(echo "$_str" |  tr ',' ' ') ; do
    if [ "$f" = "$_field" ] ; then
      _debug "'$_str' contains '$_field'"
      return 0 #contains ok
    fi
  done
  _debug "'$_str' does not contain '$_field'"
  return 1 #not contains 
}

_exists(){
  cmd="$1"
  if [ -z "$cmd" ] ; then
    _err "Usage: _exists cmd"
    return 1
  fi
  if type command >/dev/null 2>&1 ; then
    command -v "$cmd" >/dev/null 2>&1
  else
    type "$cmd" >/dev/null 2>&1
  fi
  ret="$?"
  _debug2 "$cmd exists=$ret"
  return $ret
}

#a + b
_math(){
  expr "$@"
}

#options file
_sed_i() {
  options="$1"
  filename="$2"
  if [ -z "$filename" ] ; then
    _err "Usage:_sed_i options filename"
    return 1
  fi
  _debug2 options "$options"
  if sed -h 2>&1 | grep "\-i\[SUFFIX]" >/dev/null 2>&1; then
    _debug "Using sed  -i"
    sed -i "$options" "$filename"
  else
    _debug "No -i support in sed"
    text="$(cat "$filename")"
    echo "$text" | sed "$options" > "$filename"
  fi
}

#Usage: multiline
_base64() {
  if [ "$1" ] ; then
    openssl base64 -e
  else
    openssl base64 -e | tr -d '\r\n'
  fi
}

#Usage: multiline
_dbase64() {
  if [ "$1" ] ; then
    openssl base64 -d -A
  else
    openssl base64 -d
  fi
}

# _createkey  2048|ec-256   file
_createkey() {
  length="$1"
  f="$2"
  isec=""
  if _startswith "$length" "ec-" ; then
    isec="1"
    length=$(printf $length | cut -d '-' -f 2-100)
    eccname="$length"
  fi

  if [ -z "$length" ] ; then
    if [ "$isec" ] ; then
      length=256
    else
      length=2048
    fi
  fi
  _info "Use length $length"

  if [ "$isec" ] ; then
    if [ "$length" = "256" ] ; then
      eccname="prime256v1"
    fi
    if [ "$length" = "384" ] ; then
      eccname="secp384r1"
    fi
    if [ "$length" = "521" ] ; then
      eccname="secp521r1"
    fi
    _info "Using ec name: $eccname"
  fi

  #generate account key
  if [ "$isec" ] ; then
    openssl ecparam  -name $eccname -genkey 2>/dev/null > "$f"
  else
    openssl genrsa $length 2>/dev/null > "$f"
  fi
}

#_createcsr  cn  san_list  keyfile csrfile conf
_createcsr() {
  _debug _createcsr
  domain="$1"
  domainlist="$2"
  key="$3"
  csr="$4"
  csrconf="$5"
  _debug2 domain "$domain"
  _debug2 domainlist "$domainlist"
  if [ -z "$domainlist" ] || [ "$domainlist" = "no" ]; then
    #single domain
    _info "Single domain" "$domain"
    printf "[ req_distinguished_name ]\n[ req ]\ndistinguished_name = req_distinguished_name\n" > "$csrconf"
    openssl req -new -sha256 -key "$key" -subj "/CN=$domain" -config "$csrconf" -out "$csr"
  else
    if _contains "$domainlist" "," ; then
      alt="DNS:$(echo $domainlist | sed "s/,/,DNS:/g")"
    else
      alt="DNS:$domainlist"
    fi
    #multi 
    _info "Multi domain" "$alt"
    printf "[ req_distinguished_name ]\n[ req ]\ndistinguished_name = req_distinguished_name\nreq_extensions = v3_req\n[ v3_req ]\nkeyUsage = nonRepudiation, digitalSignature, keyEncipherment\nsubjectAltName=$alt" > "$csrconf"
    openssl req -new -sha256 -key "$key" -subj "/CN=$domain" -config "$csrconf" -out "$csr"
  fi
}

_ss() {
  _port="$1"
  
  if _exists "ss" ; then
    _debug "Using: ss"
    ss -ntpl | grep ":$_port "
    return 0
  fi

  if _exists "netstat" ; then
    _debug "Using: netstat"
    if netstat -h 2>&1 | grep "\-p proto" >/dev/null ; then
      #for windows version netstat tool
      netstat -anb -p tcp | grep "LISTENING" | grep ":$_port "
    else
      if netstat -help 2>&1 | grep "\-p protocol" >/dev/null ; then
        netstat -an -p tcp | grep LISTEN | grep ":$_port "
      else
        netstat -ntpl | grep ":$_port "
      fi
    fi
    return 0
  fi

  return 1
}

toPkcs() {
  domain="$1"
  pfxPassword="$2"
  if [ -z "$domain" ] ; then
    echo "Usage: $PROJECT_ENTRY --toPkcs -d domain [--password pfx-password]"
    return 1
  fi

  _initpath "$domain"
  
  if [ "$pfxPassword" ] ; then
    openssl pkcs12 -export -out "$CERT_PFX_PATH" -inkey "$CERT_KEY_PATH" -in "$CERT_PATH" -certfile "$CA_CERT_PATH" -password "pass:$pfxPassword"
  else
    openssl pkcs12 -export -out "$CERT_PFX_PATH" -inkey "$CERT_KEY_PATH" -in "$CERT_PATH" -certfile "$CA_CERT_PATH"
  fi
  
  if [ "$?" = "0" ] ; then
    _info "Success, Pfx is exported to: $CERT_PFX_PATH"
  fi

}

#p12  password
setAPIKey() {
  _p12="$1"
  _password="$2"
  if [ -z "$_password" ] ; then
    _err "Usage: --setAPIKey  pfxfile  --password password"
    return 1
  fi
  _debug _p12 "$_p12"
  _debug _password "$_password"
  _initpath
  if _startswith "$_p12" "http" ; then
    _info "Downloading $_p12"
    if (
      cd "$STARTAPI_WORKING_DIR"
      _get "$_p12" > api.p12
    ) ; then
      _p12="$STARTAPI_WORKING_DIR/api.p12"
      _info "Download success: $_p12"
    else
      _err "Can not download $_p12"
      return 1
    fi
  fi
  _debug "Installing account key to: $ACCOUNT_KEY_PATH"
  openssl  pkcs12 -in "$_p12"   -out "$ACCOUNT_KEY_PATH"  -nocerts  -nodes  -password "pass:$_password"
  
  _debug "Installing account cert to: $ACCOUNT_CERT_PATH"
  openssl  pkcs12 -in "$_p12"   -out "$ACCOUNT_CERT_PATH"           -nodes  -password "pass:$_password"
}

# token
setAPIToken() {
  _token="$1"
  if [ -z "$_token" ] ; then
    _err "Usage: setAPIToken token"
    return 1
  fi
  _initpath
  _saveaccountconf "ACCOUNT_TOKEN" "$_token"
}

#domain length
createDomainKey() {
  _info "Creating domain key"
  if [ -z "$1" ] ; then
    echo Usage: $PROJECT_ENTRY --createDomainKey -d domain.com  [ --keylength 2048 ]
    return
  fi
  
  domain=$1
  _initpath $domain
  
  length=$2

  if [ ! -f "$CERT_KEY_PATH" ] || ( [ "$FORCE" ] && ! [ "$IS_RENEW" ] ); then 
    _createkey "$length" "$CERT_KEY_PATH"
  else
    if [ "$IS_RENEW" ] ; then
      _info "Domain key exists, skip"
      return 0
    else
      _err "Domain key exists, do you want to overwrite the key?"
      _err "Add '--force', and try again."
      return 1
    fi
  fi

}

# domain  domainlist
createCSR() {
  _info "Creating csr"
  if [ -z "$1" ] ; then
    echo "Usage: $PROJECT_ENTRY --createCSR -d domain1.com [-d domain2.com  -d domain3.com ... ]"
    return
  fi
  domain=$1
  _initpath "$domain"
  
  domainlist=$2
  
  if [ -f "$CSR_PATH" ]  && [ "$IS_RENEW" ] && [ -z "$FORCE" ]; then
    _info "CSR exists, skip"
    return
  fi
  
  _createcsr "$domain" "$domainlist" "$CERT_KEY_PATH" "$CSR_PATH" "$DOMAIN_SSL_CONF"
  
}


_time2str() {
  #BSD
  if date -u -d@$1 2>/dev/null ; then
    return
  fi
  
  #Linux
  if date -u -r $1 2>/dev/null ; then
    return
  fi
  
}

# body  url [needbase64] [POST|PUT]
_post() {
  body="$1"
  url="$2"
  needbase64="$3"
  httpmethod="$4"

  if [ -z "$httpmethod" ] ; then
    httpmethod="POST"
  fi
  _debug $httpmethod
  _debug "url" "$url"
  _debug2 "body" "$body"
  if _exists "curl" ; then
    _CURL="$CURL --dump-header $HTTP_HEADER  --key $ACCOUNT_KEY_PATH --cert $ACCOUNT_CERT_PATH "
    _debug "_CURL" "$_CURL"
    if [ "$needbase64" ] ; then
      response="$($_CURL --user-agent "$USER_AGENT" -X $httpmethod -H "$_H1" -H "$_H2" -H "$_H3" -H "$_H4" --data-urlencode "$body" "$url" | _base64)"
    else
      response="$($_CURL --user-agent "$USER_AGENT" -X $httpmethod -H "$_H1" -H "$_H2" -H "$_H3" -H "$_H4" --data-urlencode "$body" "$url" )"
    fi
    _ret="$?"
    if [ "$_ret" != "0" ] ; then
      _err "Please refer to https://curl.haxx.se/libcurl/c/libcurl-errors.html for error code: $_ret"
      if [ "$DEBUG" ] && [ "$DEBUG" -ge "2" ] ; then
        _err "Here is the curl dump log:"
        _err "$(cat "$_CURL_DUMP")"
      fi
    fi
  else
    _WGET="$WGET --certificate=\"$ACCOUNT_CERT_PATH\" --private-key=\"$ACCOUNT_KEY_PATH\" "
    _debug "_WGET" "$_WGET"
    if [ "$needbase64" ] ; then
      if [ "$httpmethod"="POST" ] ; then
        response="$($_WGET -S -O - --user-agent="$USER_AGENT" --header "$_H4" --header "$_H3" --header "$_H2" --header "$_H1" --post-data="$body" "$url" 2>"$HTTP_HEADER" | _base64)"
      else
        response="$($_WGET -S -O - --user-agent="$USER_AGENT" --header "$_H4" --header "$_H3" --header "$_H2" --header "$_H1" --method $httpmethod --body-data="$body" "$url" 2>"$HTTP_HEADER" | _base64)"
      fi
    else
      if [ "$httpmethod"="POST" ] ; then
        response="$($_WGET -S -O - --user-agent="$USER_AGENT" --header "$_H4" --header "$_H3" --header "$_H2" --header "$_H1" --post-data="$body" "$url" 2>"$HTTP_HEADER")"
      else
        response="$($_WGET -S -O - --user-agent="$USER_AGENT" --header "$_H4" --header "$_H3" --header "$_H2" --header "$_H1" --method $httpmethod --body-data="$body" "$url" 2>"$HTTP_HEADER")"
      fi
    fi
    _ret="$?"
    if [ "$_ret" != "0" ] ; then
      _err "Please refer to https://www.gnu.org/software/wget/manual/html_node/Exit-Status.html for error code: $_ret" 
    fi
    _sed_i "s/^ *//g" "$HTTP_HEADER"
  fi
  _debug "_ret" "$_ret"
  printf "%s" "$response"
  return $_ret
}

# url getheader
_get() {
  _debug GET
  url="$1"
  onlyheader="$2"
  _debug url $url
  if _exists "curl" ; then
    _debug "CURL" "$CURL"
    if [ "$onlyheader" ] ; then
      $CURL -I --user-agent "$USER_AGENT" -H "$_H1" -H "$_H2" -H "$_H3" -H "$_H4" $url
    else
      $CURL    --user-agent "$USER_AGENT" -H "$_H1" -H "$_H2" -H "$_H3" -H "$_H4" $url
    fi
    ret=$?
  else
    _debug "WGET" "$WGET"
    if [ "$onlyheader" ] ; then
      $WGET --user-agent="$USER_AGENT" --header "$_H4" --header "$_H3" --header "$_H2" --header "$_H1" -S -O /dev/null $url 2>&1 | sed 's/^[ ]*//g'
    else
      $WGET --user-agent="$USER_AGENT" --header "$_H4" --header "$_H3" --header "$_H2" --header "$_H1"    -O - $url
    fi
    ret=$?
  fi
  _debug "ret" "$ret"
  return $ret
}


#_startapi token action  arg
_startapi() {

  action="$1"
  arg="$2"
  
  token="$ACCOUNT_TOKEN"
  starturi="$API"
  
  data="{\"tokenID\":\"$token\",\"actionType\":\"$action\""
  if [ "$arg" ] ; then
    data="$data,$arg}"
  else
    data="$data}"
  fi
  
  _debug2 data "$data"
  
  _response="$(_post "RequestData=$data" "$starturi")"
  _ret="$?"
  if [ "$_ret" != "0" ] ; then
    _err "_startapi error: $(echo $_response | grep shortMsg)"
    return 1
  fi
  _debug2 "_response" "$_response"
  printf "%s" "$_response"
  
}

#ApplyCertificate domain domains csr certType uid emails employeeName
_ApplyCertificate() {
  domain="$1"
  domains="$2"
  csr="$3"
  certType="$4"
  if [ -z "$certType" ] ; then
    certType="DVSSL"
  fi
  uid="$5"
  emails="$6"
  employeeName="$7"
  
  
  _initpath $domain
  
  if [ -z "$csr" ] ; then
    csr="$(cat "$CSR_PATH")"
  fi
  
  arg="\"certType\":\"$certType\",\"domains\":\"$domains\",\"emails\":\"$emails\",\"employeeName\":\"$employeeName\",\"CSR\":\"$csr\",\"userID\":\"$uid\""

  _startapi "ApplyCertificate" "$arg"
  
}


#ApplyWebControl domain
_ApplyWebControl() {
  domain="$1"
  
  _initpath $domain
  
  arg="\"hostname\":\"$domain\""

  _startapi "ApplyWebControl" "$arg"

}

#WebControlValidation domain
_WebControlValidation() {
  domain="$1"
  
  _initpath $domain
  
  arg="\"hostname\":\"$domain\""

  _startapi "WebControlValidation" "$arg"

}

#queryvalidateddomains
_queryvalidateddomains() {
  _initpath
  _startapi "queryvalidateddomains" | grep "^ *\"data\":" | cut -d : -f 2 | tr -d " \"\r\n"
}


#_querywhois domain
_querywhois() {
  domain="$1"
  
  _initpath $domain
  
  arg="\"domain\":\"$domain\""

  _startapi "querywhois" "$arg"

}


#ApplyDomainVerification domain email uid
_ApplyDomainVerification() {
  domain="$1"
  email="$2"
  uid="$3"
  
  _initpath $domain
  
  arg="\"domain\":\"$domain\",\"authenEmail\":\"$email\",\"userID\":\"$uid\""

  _startapi "ApplyDomainVerification" "$arg"

}

#Domainvalidation domain email uid authcode
_Domainvalidation() {
  domain="$1"
  email="$2"
  uid="$3"
  authcode="$4"
  
  _initpath $domain
  
  arg="\"domain\":\"$domain\",\"authenEmail\":\"$email\",\"userID\":\"$uid\",\"authcode\":\"cJVhtnh5qJfRpk\""

  _startapi "Domainvalidation" "$arg"

}

#_adduser  
_adduser() {

  _initpath $domain
  
  arg="\"domain\":\"$domain\",\"authenEmail\":\"$email\",\"userID\":\"$uid\",\"authcode\":\"cJVhtnh5qJfRpk\""

  _startapi "Domainvalidation" "$arg"
  
}

#QueryUserInfo uid
_QueryUserInfo() {
  uid="$1"
  
  _initpath
  arg="\"userID\":\"$uid\""

  _startapi "QueryUserInfo" "$arg"
}


#_UploadProofDocument  uid file64
_UploadProofDocument() {

  uid="$1"
  file64="$2"
  
  _initpath
  arg="\"userID\":\"$uid\",\"ProofDoc\":\"$file64\""
  
  _startapi "UploadProofDocument" "$arg"
  
}


#revokeRequest orderid
_revokeRequest() {
  orderid="$1"
  
  _initpath
  arg="\"orderID\":\"$orderid\""
  
  _startapi "revokeRequest" "$arg"
  
}

#applyemailverification email
_applyemailverification() {
  email="$1"
  _initpath
  
  arg="\"email\":\"$email\""
  
  _startapi "applyemailverification" "$arg"
}

#emailvalidation  email  authcode  uid
_emailvalidation() {
  email="$1"
  authcode="$2"
  uid="$3"
  
  _initpath
  
  arg="\"email\":\"$email\",\"authcode\":\"$authcode\",\"userID\":\"$uid\""
  
  _startapi "emailvalidation" "$arg"
}


#queryvalidatedemails  uid
_queryvalidatedemails() {
  uid="$1"
  
  _initpath
  
  arg="\"userID\":\"$uid\""
  
  _startapi "queryvalidatedemails" "$arg"
  
}


#setopt "file"  "opt"  "="  "value" [";"]
_setopt() {
  __conf="$1"
  __opt="$2"
  __sep="$3"
  __val="$4"
  __end="$5"
  if [ -z "$__opt" ] ; then 
    echo usage: _setopt  '"file"  "opt"  "="  "value" [";"]'
    return
  fi
  if [ ! -f "$__conf" ] ; then
    touch "$__conf"
  fi

  if grep -H -n "^$__opt$__sep" "$__conf" > /dev/null ; then
    _debug2 OK
    if _contains "$__val" "&" ; then
      __val="$(echo $__val | sed 's/&/\\&/g')"
    fi
    text="$(cat $__conf)"
    echo "$text" | sed "s|^$__opt$__sep.*$|$__opt$__sep$__val$__end|" > "$__conf"

  elif grep -H -n "^#$__opt$__sep" "$__conf" > /dev/null ; then
    if _contains "$__val" "&" ; then
      __val="$(echo $__val | sed 's/&/\\&/g')"
    fi
    text="$(cat $__conf)"
    echo "$text" | sed "s|^#$__opt$__sep.*$|$__opt$__sep$__val$__end|" > "$__conf"

  else
    _debug2 APP
    echo "$__opt$__sep$__val$__end" >> "$__conf"
  fi
  _debug "$(grep -H -n "^$__opt$__sep" $__conf)"
}

#_savedomainconf   key  value
#save to domain.conf
_savedomainconf() {
  key="$1"
  value="$2"
  if [ "$DOMAIN_CONF" ] ; then
    _setopt "$DOMAIN_CONF" "$key" "=" "\"$value\""
  else
    _err "DOMAIN_CONF is empty, can not save $key=$value"
  fi
}

#_cleardomainconf   key
_cleardomainconf() {
  key="$1"
  if [ "$DOMAIN_CONF" ] ; then
    _sed_i "s/^$key.*$//"  "$DOMAIN_CONF"
  else
    _err "DOMAIN_CONF is empty, can not save $key=$value"
  fi
}

#_saveaccountconf  key  value
_saveaccountconf() {
  key="$1"
  value="$2"
  if [ "$ACCOUNT_CONF_PATH" ] ; then
    _setopt "$ACCOUNT_CONF_PATH" "$key" "=" "\"$value\""
  else
    _err "ACCOUNT_CONF_PATH is empty, can not save $key=$value"
  fi
}

_startserver() {
  content="$1"
  _debug "startserver: $$"
  nchelp="$(nc -h 2>&1)"
  
  if echo "$nchelp" | grep "\-q[ ,]" >/dev/null ; then
    _NC="nc -q 1 -l"
  else
    if echo "$nchelp" | grep "GNU netcat" >/dev/null && echo "$nchelp" | grep "\-c, \-\-close" >/dev/null ; then
      _NC="nc -c -l"
    elif echo "$nchelp" | grep "\-N" |grep "Shutdown the network socket after EOF on stdin"  >/dev/null ; then
      _NC="nc -N -l"
    else
      _NC="nc -l"
    fi
  fi

  _debug "_NC" "$_NC"
  _debug Le_HTTPPort "$Le_HTTPPort"
#  while true ; do
    if [ "$DEBUG" ] ; then
      if ! printf "HTTP/1.1 200 OK\r\n\r\n$content" | $_NC -p $Le_HTTPPort ; then
        printf "HTTP/1.1 200 OK\r\n\r\n$content" | $_NC $Le_HTTPPort ;
      fi
    else
      if ! printf "HTTP/1.1 200 OK\r\n\r\n$content" | $_NC -p $Le_HTTPPort > /dev/null 2>&1; then
        printf "HTTP/1.1 200 OK\r\n\r\n$content" | $_NC $Le_HTTPPort > /dev/null 2>&1
      fi      
    fi
    if [ "$?" != "0" ] ; then
      _err "nc listen error."
      exit 1
    fi
#  done
}

_stopserver(){
  pid="$1"
  _debug "pid" "$pid"
  if [ -z "$pid" ] ; then
    return
  fi

  _get "http://localhost:$Le_HTTPPort" >/dev/null 2>&1
  _get "https://localhost:$Le_TLSPort" >/dev/null 2>&1

}


_initpath() {

  if [ -z "$STARTAPI_WORKING_DIR" ] ; then
    STARTAPI_WORKING_DIR=$HOME/.$PROJECT_NAME
  fi
  
  _DEFAULT_ACCOUNT_CONF_PATH="$STARTAPI_WORKING_DIR/account.conf"

  if [ -z "$ACCOUNT_CONF_PATH" ] ; then
    if [ -f "$_DEFAULT_ACCOUNT_CONF_PATH" ] ; then
      . "$_DEFAULT_ACCOUNT_CONF_PATH"
    fi
  fi
  
  if [ -z "$ACCOUNT_CONF_PATH" ] ; then
    ACCOUNT_CONF_PATH="$_DEFAULT_ACCOUNT_CONF_PATH"
  fi
  
  if [ -f "$ACCOUNT_CONF_PATH" ] ; then
    . "$ACCOUNT_CONF_PATH"
  fi

  if [ "$IN_CRON" ] ; then
    if [ ! "$_USER_PATH_EXPORTED" ] ; then
      _USER_PATH_EXPORTED=1
      export PATH="$USER_PATH:$PATH"
    fi
  fi

  if [ -z "$API" ] ; then
    if [ -z "$STAGE" ] ; then
      API="$DEFAULT_CA"
    else
      API="$STAGE_CA"
      _info "Using stage api:$API"
    fi  
  fi

  
  if [ -z "$USER_AGENT" ] ; then
    USER_AGENT="$DEFAULT_USER_AGENT"
  fi
  
  _DEFAULT_ACCOUNT_KEY_PATH="$STARTAPI_WORKING_DIR/account.key"
  if [ -z "$ACCOUNT_KEY_PATH" ] ; then
    ACCOUNT_KEY_PATH="$_DEFAULT_ACCOUNT_KEY_PATH"
  fi
  _debug "ACCOUNT_KEY_PATH" "$ACCOUNT_KEY_PATH"
  _DEFAULT_ACCOUNT_CERT_PATH="$STARTAPI_WORKING_DIR/account.cer"
  if [ -z "$ACCOUNT_CERT_PATH" ] ; then
    ACCOUNT_CERT_PATH="$_DEFAULT_ACCOUNT_CERT_PATH"
  fi
  
  HTTP_HEADER="$STARTAPI_WORKING_DIR/http.header"
  
  WGET="wget -q "
  if [ "$DEBUG" ] && [ "$DEBUG" -ge "2" ] ; then
    WGET="$WGET -d "
  fi

  _CURL_DUMP="$STARTAPI_WORKING_DIR/curl.dump"
  CURL="curl -L --silent "
  if [ "$DEBUG" ] && [ "$DEBUG" -ge "2" ] ; then
    CURL="$CURL --trace-ascii $_CURL_DUMP "
  fi

  if [ "$Le_Insecure" ] ; then
    WGET="$WGET --no-check-certificate "
    CURL="$CURL --insecure  "
  fi

  _DEFAULT_CERT_HOME="$STARTAPI_WORKING_DIR"
  if [ -z "$CERT_HOME" ] ; then
    CERT_HOME="$_DEFAULT_CERT_HOME"
  fi


  domain="$1"

  if [ -z "$domain" ] ; then
    return 0
  fi
  
  domainhome="$CERT_HOME/$domain"
  mkdir -p "$domainhome"

  if [ -z "$DOMAIN_PATH" ] ; then
    DOMAIN_PATH="$domainhome"
  fi
  if [ -z "$DOMAIN_CONF" ] ; then
    DOMAIN_CONF="$domainhome/$domain.conf"
  fi
  
  if [ -z "$DOMAIN_SSL_CONF" ] ; then
    DOMAIN_SSL_CONF="$domainhome/$domain.ssl.conf"
  fi
  
  if [ -z "$CSR_PATH" ] ; then
    CSR_PATH="$domainhome/$domain.csr"
  fi
  if [ -z "$CERT_KEY_PATH" ] ; then 
    CERT_KEY_PATH="$domainhome/$domain.key"
  fi
  if [ -z "$CERT_PATH" ] ; then
    CERT_PATH="$domainhome/$domain.cer"
  fi
  if [ -z "$CA_CERT_PATH" ] ; then
    CA_CERT_PATH="$domainhome/ca.cer"
  fi
  if [ -z "$CERT_FULLCHAIN_PATH" ] ; then
    CERT_FULLCHAIN_PATH="$domainhome/fullchain.cer"
  fi
  if [ -z "$CERT_PFX_PATH" ] ; then
    CERT_PFX_PATH="$domainhome/$domain.pfx"
  fi
  
  if [ -z "$CERT_ORDER_PATH" ] ; then
    CERT_ORDER_PATH="$domainhome/$domain.order"
  fi

  
}

_clearup() {
  _stopserver $serverproc
  serverproc=""
}


#validated_list  domain
_isValidated() {
  _validated_list="$1"
  _domain="$2"
  alldomains=$(echo "$_validated_list" |  tr ',' ' ' )
  for _d in $alldomains
  do
    if [ "$_d" = "$_domain" ] ; then
      return 0
    fi
    
    if _endswith "$_domain" ".$_d" ; then
      return 0
    fi
  done
  return 1
}

# webroot  removelevel tokenfile
_clearupwebbroot() {
  __webroot="$1"
  if [ -z "$__webroot" ] ; then
    _debug "no webroot specified, skip"
    return 0
  fi
  
  if [ "$2" ] ; then 
    _debug "remove $__webroot/$3"
    rm -rf "$__webroot/$3"
  else
    _debug "Skip for removelevel:$2"
  fi
  return 0

}

issue() {
  if [ -z "$2" ] ; then
    echo "Usage: $PROJECT_ENTRY --issue  -d  a.com  -w /path/to/webroot/a.com/ "
    return 1
  fi
  Le_Webroot="$1"
  Le_Domain="$2"
  Le_Alt="$3"
  Le_Keylength="$4"
  Le_RealCertPath="$5"
  Le_RealKeyPath="$6"
  Le_RealCACertPath="$7"
  Le_ReloadCmd="$8"
  Le_RealFullChainPath="$9"
  Le_CertType="${10}"

  _initpath $Le_Domain

  if [ -f "$DOMAIN_CONF" ] ; then
    Le_NextRenewTime=$(grep "^Le_NextRenewTime=" "$DOMAIN_CONF" | cut -d '=' -f 2 | tr -d "'\"")
    _debug Le_NextRenewTime "$Le_NextRenewTime"
    if [ -z "$FORCE" ] && [ "$Le_NextRenewTime" ] && [ $(date -u "+%s" ) -lt $Le_NextRenewTime ] ; then 
      _info "Skip, Next renewal time is: $(grep "^Le_NextRenewTimeStr" "$DOMAIN_CONF" | cut -d '=' -f 2)"
      return $RENEW_SKIP
    fi
  fi

  _savedomainconf "Le_Domain"       "$Le_Domain"
  _savedomainconf "Le_Alt"          "$Le_Alt"
  _savedomainconf "Le_Webroot"      "$Le_Webroot"
  _savedomainconf "Le_Keylength"    "$Le_Keylength"
  if [ "$Le_CertType" ] ; then
    _savedomainconf "Le_CertType"    "$Le_CertType"
  fi
  
  if [ "$Le_Alt" = "no" ] ; then
    Le_Alt=""
  fi
  if [ "$Le_Keylength" = "no" ] ; then
    Le_Keylength=""
  fi
  
  if _hasfield "$Le_Webroot" "no" ; then
    _info "Standalone mode."
    if ! _exists "nc" ; then
      _err "Please install netcat(nc) tools first."
      return 1
    fi
    
    if [ -z "$Le_HTTPPort" ] ; then
      Le_HTTPPort=80
    else
      _savedomainconf "Le_HTTPPort"  "$Le_HTTPPort"
    fi    
    
    netprc="$(_ss "$Le_HTTPPort" | grep "$Le_HTTPPort")"
    if [ "$netprc" ] ; then
      _err "$netprc"
      _err "tcp port $Le_HTTPPort is already used by $(echo "$netprc" | cut -d :  -f 4)"
      _err "Please stop it first"
      return 1
    fi
  fi

  

  if [ ! -f "$ACCOUNT_KEY_PATH" ] ; then
    _err "Please give account key first."
    return 1
  fi
  
  if [ -z "$ACCOUNT_TOKEN" ] ; then
    _err "Please set account api token first."
    return 1
  fi

  if [ ! -f "$CERT_KEY_PATH" ] ; then
    if ! createDomainKey $Le_Domain $Le_Keylength ; then 
      _err "Create domain key error."
      _clearup
      return 1
    fi
  fi
  
  if ! createCSR  $Le_Domain  $Le_Alt ; then
    _err "Create CSR error."
    _clearup
    return 1
  fi

  vlist="$Le_Vlist"
  # verify each domain
  _info "Verify each domain"
  validatedDomains="$(_queryvalidateddomains)"
  _debug "validatedDomains" "$validatedDomains"
  sep='#'
  if [ -z "$vlist" ] ; then
    alldomains=$(echo "$Le_Domain,$Le_Alt" |  tr ',' ' ' )
    _index=1
    _currentRoot=""
    for d in $alldomains   
    do
      _info "Getting webroot for domain" $d
      _w="$(echo $Le_Webroot | cut -d , -f $_index)"
      _debug _w "$_w"
      if [ "$_w" ] ; then
        _currentRoot="$_w"
      fi
      _debug "_currentRoot" "$_currentRoot"
      _index=$(_math $_index + 1)

      if _startswith "$d" '*.' ; then
        _info "Wildcard: $d"
        d="$(echo "$d" |  cut -d . -f 2-99)"
      fi

      if _isValidated "$validatedDomains" "$d" ; then
        token="$TOKEN_OK"
      else
        vtype="$VTYPE_HTTP"

        _info "Getting token for domain" $d
        
        response="$(_ApplyWebControl "$d")"
        if ! printf "%s" "$response" | grep '"status" *: *1' >/dev/null 2>&1 ; then
          _err "Get token error: $response"
          _clearup
          return 1
        fi

        if [ "$vtype" = "$VTYPE_HTTP" ] ; then
          entry="$(printf "%s" "$response" | grep ' *"data" *:'| tr -d "\r\n")"
        else
          #todo: not support email yet
          _err "Not implement for: $vtype"
          _clearup
          return 1
        fi
        
        _debug entry "$entry"
        if [ -z "$entry" ] ; then
          _err "Error, can not get domain token $d"
          _clearup
          return 1
        fi
        token="$(printf "%s" "$entry" | cut -d : -f 2 | tr -d '" ' )"
      fi

      _debug token $token
      
      dvlist="$d$sep$token$sep$vtype$sep$_currentRoot"
      _debug dvlist "$dvlist"
      vlist="$vlist$dvlist,"
    done
  fi

  _debug "ok, let's start to verify"
  ventries=$(echo "$vlist" |  tr ',' ' ' )
  for ventry in $ventries
  do
    d=$(echo $ventry | cut -d $sep -f 1)
    token=$(echo $ventry | cut -d $sep -f 2)
    vtype=$(echo $ventry | cut -d $sep -f 3)
    _currentRoot=$(echo $ventry | cut -d $sep -f 4)

    _info "Verifying:$d"
    _debug "d" "$d"
    _debug "token" "$token"
    _debug "vtype" "$vtype"
    _debug "_currentRoot" "$_currentRoot"

    if [ "$token" = "$TOKEN_OK" ] ; then
      _info "$d is already validated, skip."
      continue
    fi

    validatedDomains="$(_queryvalidateddomains)"
    _debug "validatedDomains" "$validatedDomains"
  
    if _startswith "$d" '*.' ; then
      _info "Wildcard: $d"
      d="$(echo "$d" |  cut -d . -f 2-99)"
    fi

    if _isValidated "$validatedDomains" "$d" ; then
      _info "$d is already validated, skip."
      continue
    fi
        
    removelevel=""
    if [ "$vtype" = "$VTYPE_HTTP" ] ; then
      if [ "$_currentRoot" = "no" ] ; then
        _info "Standalone mode server"
        _startserver "$token" &
        if [ "$?" != "0" ] ; then
          _clearup
          return 1
        fi
        serverproc="$!"
        sleep 2
        _debug serverproc $serverproc

      else
        wellknown_path="$_currentRoot"
        removelevel='3'
        _debug wellknown_path "$wellknown_path"

        _debug "writing token:$token to $wellknown_path/$d.html"

        mkdir -p "$wellknown_path"
        printf "%s" "$token" > "$wellknown_path/$d.html"
        
      fi

    fi

    waittimes=0
    if [ -z "$MAX_RETRY_TIMES" ] ; then
      MAX_RETRY_TIMES=30
    fi
    
    while true ; do
      waittimes=$(_math $waittimes + 1)
      if [ "$waittimes" -ge "$MAX_RETRY_TIMES" ] ; then
        _err "$d:Timeout"
        _clearupwebbroot "$_currentRoot" "$removelevel" "$d.html"
        _clearup
        return 1
      fi
      
      _debug "sleep 5 secs to verify"
      sleep 5
      _debug "checking"
      
      response="$(_WebControlValidation $d)"

      _debug2 original "$response"

      status=$(echo "$response" | grep '"shortMsg *": *"success"')
      
      if [ "$status" ] ; then
        _info "Success"
        _stopserver $serverproc
        serverproc=""
        _clearupwebbroot "$_currentRoot" "$removelevel" "$d.html"
        break;
      fi
      
      error="$(echo $response | grep  '"shortMsg":')"
      _err "$d:Verify error:$error"
      _clearupwebbroot "$_currentRoot" "$removelevel" "$d.html"
      _clearup
      return 1;
      
    done
    
  done

  _clearup
  _info "Verify finished, start to sign."
  
  if ! _ApplyCertificate $Le_Domain  "$Le_Domain,$Le_Alt" "" "$Le_CertType" > "$CERT_ORDER_PATH" ; then
    _err "Apply certificate error."
    return 1
  fi

  if [ ! "$USER_PATH" ] || [ ! "$IN_CRON" ] ; then
    USER_PATH="$PATH"
    _saveaccountconf "USER_PATH" "$USER_PATH"
  fi
    
  grep ' *"certificate":' "$CERT_ORDER_PATH" | cut -d : -f 2 | tr -d " \"" | _dbase64 "multiline" > "$CERT_PATH"
  
  _info "Cert success."
  cat "$CERT_PATH"
    
  grep ' *"intermediateCertificate":' "$CERT_ORDER_PATH" | cut -d : -f 2 | tr -d " \"" | _dbase64 "multiline" > "$CA_CERT_PATH"
  
  cp "$CERT_PATH" "$CERT_FULLCHAIN_PATH"
  
  cat "$CA_CERT_PATH" >> "$CERT_FULLCHAIN_PATH"
  
  _cleardomainconf  "Le_Vlist"  

  Le_CertCreateTime=$(date -u "+%s")
  _savedomainconf  "Le_CertCreateTime"   "$Le_CertCreateTime"
  
  Le_CertCreateTimeStr=$(date -u )
  _savedomainconf  "Le_CertCreateTimeStr"  "$Le_CertCreateTimeStr"
  
  if [ -z "$Le_RenewalDays" ] || [ "$Le_RenewalDays" -lt "0" ] || [ "$Le_RenewalDays" -gt "$MAX_RENEW" ] ; then
    Le_RenewalDays=$MAX_RENEW
  else
    _savedomainconf  "Le_RenewalDays"   "$Le_RenewalDays"
  fi  

  Le_NextRenewTime=$(_math $Le_CertCreateTime + $Le_RenewalDays \* 24 \* 60 \* 60)
  _savedomainconf "Le_NextRenewTime"   "$Le_NextRenewTime"
  
  Le_NextRenewTimeStr=$( _time2str $Le_NextRenewTime )
  _savedomainconf  "Le_NextRenewTimeStr"  "$Le_NextRenewTimeStr"


  _output="$(installcert $Le_Domain  "$Le_RealCertPath" "$Le_RealKeyPath" "$Le_RealCACertPath" "$Le_ReloadCmd" "$Le_RealFullChainPath" 2>&1)"
  _ret="$?"
  if [ "$_ret" = "9" ] ; then
    #ignore the empty install error.
    return 0
  fi
  if [ "$_ret" != "0" ] ; then
    _err "$_output"
    return 1
  fi
}

renew() {
  Le_Domain="$1"
  if [ -z "$Le_Domain" ] ; then
    _err "Usage: $PROJECT_ENTRY --renew  -d domain.com"
    return 1
  fi

  _initpath $Le_Domain
  _info "Renew: $Le_Domain"
  if [ ! -f "$DOMAIN_CONF" ] ; then
    _info "$Le_Domain is not a issued domain, skip."
    return 0;
  fi
  
  . "$DOMAIN_CONF"
  if [ -z "$FORCE" ] && [ "$Le_NextRenewTime" ] && [ "$(date -u "+%s" )" -lt "$Le_NextRenewTime" ] ; then 
    _info "Skip, Next renewal time is: $Le_NextRenewTimeStr"
    return $RENEW_SKIP
  fi
  
  IS_RENEW="1"
  issue "$Le_Webroot" "$Le_Domain" "$Le_Alt" "$Le_Keylength" "$Le_RealCertPath" "$Le_RealKeyPath" "$Le_RealCACertPath" "$Le_ReloadCmd" "$Le_RealFullChainPath" "$Le_CertType"
  local res=$?
  IS_RENEW=""

  return $res
}

#renewAll  [stopRenewOnError]
renewAll() {
  _initpath
  _stopRenewOnError="$1"
  _debug "_stopRenewOnError" "$_stopRenewOnError"
  _ret="0"
  for d in $(ls -F ${CERT_HOME}/ | grep [^.].*[.].*/$ ) ; do
    d=$(echo $d | cut -d '/' -f 1)
    ( 
      renew "$d"
    )
    rc="$?"
    _debug "Return code: $rc"
    if [ "$rc" != "0" ] ; then
      if [ "$rc" = "$RENEW_SKIP" ] ; then
        _info "Skipped $d"
      elif [ "$_stopRenewOnError" ] ; then
        _err "Error renew $d,  stop now."
        return $rc
      else
        _ret="$rc"
        _err "Error renew $d, Go ahead to next one."
      fi
    fi
  done
  return $_ret
}


list() {
  local _raw="$1"
  _initpath
  
  _sep="|"
  if [ "$_raw" ] ; then
    printf  "Main_Domain${_sep}SAN_Domains${_sep}Created${_sep}Renew\n"
    for d in $(ls -F ${CERT_HOME}/ | grep [^.].*[.].*/$ ) ; do
      d=$(echo $d | cut -d '/' -f 1)
      (
        _initpath $d
        if [ -f "$DOMAIN_CONF" ] ; then
          . "$DOMAIN_CONF"
          printf "$Le_Domain${_sep}$Le_Alt${_sep}$Le_CertCreateTimeStr${_sep}$Le_NextRenewTimeStr\n"
        fi
      )
    done
  else
    list "raw" | column -t -s "$_sep"  
  fi


}

installcert() {
  Le_Domain="$1"
  if [ -z "$Le_Domain" ] ; then
    echo "Usage: $PROJECT_ENTRY --installcert -d domain.com  [--certpath cert-file-path]  [--keypath key-file-path]  [--capath ca-cert-file-path]   [ --reloadCmd reloadCmd] [--fullchainpath fullchain-path]"
    return 1
  fi

  Le_RealCertPath="$2"
  Le_RealKeyPath="$3"
  Le_RealCACertPath="$4"
  Le_ReloadCmd="$5"
  Le_RealFullChainPath="$6"

  _initpath $Le_Domain

  _savedomainconf "Le_RealCertPath"         "$Le_RealCertPath"
  _savedomainconf "Le_RealCACertPath"       "$Le_RealCACertPath"
  _savedomainconf "Le_RealKeyPath"          "$Le_RealKeyPath"
  _savedomainconf "Le_ReloadCmd"            "$Le_ReloadCmd"
  _savedomainconf "Le_RealFullChainPath"    "$Le_RealFullChainPath"
  
  if [ "$Le_RealCertPath" = "no" ] ; then
    Le_RealCertPath=""
  fi
  if [ "$Le_RealKeyPath" = "no" ] ; then
    Le_RealKeyPath=""
  fi
  if [ "$Le_RealCACertPath" = "no" ] ; then
    Le_RealCACertPath=""
  fi
  if [ "$Le_ReloadCmd" = "no" ] ; then
    Le_ReloadCmd=""
  fi
  if [ "$Le_RealFullChainPath" = "no" ] ; then
    Le_RealFullChainPath=""
  fi
  
  _installed="0"
  if [ "$Le_RealCertPath" ] ; then
    _installed=1
    _info "Installing cert to:$Le_RealCertPath"
    if [ -f "$Le_RealCertPath" ] ; then
      cp "$Le_RealCertPath" "$Le_RealCertPath".bak
    fi
    cat "$CERT_PATH" > "$Le_RealCertPath"
  fi
  
  if [ "$Le_RealCACertPath" ] ; then
    _installed=1
    _info "Installing CA to:$Le_RealCACertPath"
    if [ "$Le_RealCACertPath" = "$Le_RealCertPath" ] ; then
      echo "" >> "$Le_RealCACertPath"
      cat "$CA_CERT_PATH" >> "$Le_RealCACertPath"
    else
      if [ -f "$Le_RealCACertPath" ] ; then
        cp "$Le_RealCACertPath" "$Le_RealCACertPath".bak
      fi
      cat "$CA_CERT_PATH" > "$Le_RealCACertPath"
    fi
  fi


  if [ "$Le_RealKeyPath" ] ; then
    _installed=1
    _info "Installing key to:$Le_RealKeyPath"
    if [ -f "$Le_RealKeyPath" ] ; then
      cp "$Le_RealKeyPath" "$Le_RealKeyPath".bak
    fi
    cat "$CERT_KEY_PATH" > "$Le_RealKeyPath"
  fi
  
  if [ "$Le_RealFullChainPath" ] ; then
    _installed=1
    _info "Installing full chain to:$Le_RealFullChainPath"
    if [ -f "$Le_RealFullChainPath" ] ; then
      cp "$Le_RealFullChainPath" "$Le_RealFullChainPath".bak
    fi
    cat "$CERT_FULLCHAIN_PATH" > "$Le_RealFullChainPath"
  fi  

  if [ "$Le_ReloadCmd" ] ; then
    _installed=1
    _info "Run Le_ReloadCmd: $Le_ReloadCmd"
    if (cd "$DOMAIN_PATH" && eval "$Le_ReloadCmd") ; then
      _info "Reload success."
    else
      _err "Reload error for :$Le_Domain"
    fi
  fi

  if [ "$_installed" = "0" ] ; then
    _err "Nothing to install. You don't specify any parameter."
    return 9
  fi

}

installcronjob() {
  _initpath
  if ! _exists "crontab" ; then
    _err "crontab doesn't exist, so, we can not install cron jobs."
    _err "All your certs will not be renewed automatically."
    _err "You must add your own cron job to call '$PROJECT_ENTRY --cron' everyday."
    return 1
  fi

  _info "Installing cron job"
  if ! crontab -l | grep "$PROJECT_ENTRY --cron" ; then 
    if [ -f "$STARTAPI_WORKING_DIR/$PROJECT_ENTRY" ] ; then
      lesh="\"$STARTAPI_WORKING_DIR\"/$PROJECT_ENTRY"
    else
      _err "Can not install cronjob, $PROJECT_ENTRY not found."
      return 1
    fi
    crontab -l | { cat; echo "0 0 * * * $lesh --cron --home \"$STARTAPI_WORKING_DIR\" > /dev/null"; } | crontab -
  fi
  if [ "$?" != "0" ] ; then
    _err "Install cron job failed. You need to manually renew your certs."
    _err "Or you can add cronjob by yourself:"
    _err "$lesh --cron --home \"$STARTAPI_WORKING_DIR\" > /dev/null"
    return 1
  fi
}

uninstallcronjob() {
  if ! _exists "crontab" ; then
    return
  fi
  _info "Removing cron job"
  cr="$(crontab -l | grep "$PROJECT_ENTRY --cron")"
  if [ "$cr" ] ; then 
    crontab -l | sed "/$PROJECT_ENTRY --cron/d" | crontab -
    STARTAPI_WORKING_DIR="$(echo "$cr" | cut -d ' ' -f 9 | tr -d '"')"
    _info STARTAPI_WORKING_DIR "$STARTAPI_WORKING_DIR"
  fi 
  _initpath

}

revoke() {
  Le_Domain="$1"
  if [ -z "$Le_Domain" ] ; then
    echo "Usage: $PROJECT_ENTRY --revoke -d domain.com"
    return 1
  fi
  
  _initpath $Le_Domain
  if [ ! -f "$DOMAIN_CONF" ] ; then
    _err "$Le_Domain is not a issued domain, skip."
    return 1;
  fi
  
  if [ ! -f "$CERT_PATH" ] ; then
    _err "Cert for $Le_Domain $CERT_PATH is not found, skip."
    return 1
  fi
  
  _err "Not implemented yet."
  return 1
}

# Detect profile file if not specified as environment variable
_detect_profile() {
  if [ -n "$PROFILE" -a -f "$PROFILE" ] ; then
    echo "$PROFILE"
    return
  fi

  local DETECTED_PROFILE
  DETECTED_PROFILE=''
  local SHELLTYPE
  SHELLTYPE="$(basename "/$SHELL")"

  if [ "$SHELLTYPE" = "bash" ] ; then
    if [ -f "$HOME/.bashrc" ] ; then
      DETECTED_PROFILE="$HOME/.bashrc"
    elif [ -f "$HOME/.bash_profile" ] ; then
      DETECTED_PROFILE="$HOME/.bash_profile"
    fi
  elif [ "$SHELLTYPE" = "zsh" ] ; then
    DETECTED_PROFILE="$HOME/.zshrc"
  fi

  if [ -z "$DETECTED_PROFILE" ] ; then
    if [ -f "$HOME/.profile" ] ; then
      DETECTED_PROFILE="$HOME/.profile"
    elif [ -f "$HOME/.bashrc" ] ; then
      DETECTED_PROFILE="$HOME/.bashrc"
    elif [ -f "$HOME/.bash_profile" ] ; then
      DETECTED_PROFILE="$HOME/.bash_profile"
    elif [ -f "$HOME/.zshrc" ] ; then
      DETECTED_PROFILE="$HOME/.zshrc"
    fi
  fi

  if [ ! -z "$DETECTED_PROFILE" ] ; then
    echo "$DETECTED_PROFILE"
  fi
}

_initconf() {
  _initpath
  if [ ! -f "$ACCOUNT_CONF_PATH" ] ; then
    echo "#ACCOUNT_CONF_PATH=xxxx

#Account configurations:
#Here are the supported macros, uncomment them to make them take effect.

#ACCOUNT_TOKEN=XXXXXXXXX  # the account TOKEN.

#ACCOUNT_KEY_PATH=\"/path/to/account.key\"
#CERT_HOME=\"/path/to/cert/home\"

#STAGE=1 # Use the staging api
#FORCE=1 # Force to issue cert
#DEBUG=1 # Debug mode

#ACCOUNT_KEY_HASH=account key hash

#USER_AGENT=\"$USER_AGENT\"

#USER_PATH=""

    " > $ACCOUNT_CONF_PATH
  fi
}

# nocron
_precheck() {
  _nocron="$1"
  
  if ! _exists "curl"  && ! _exists "wget"; then
    _err "Please install curl or wget first, we need to access http resources."
    return 1
  fi
  
  if [ -z "$_nocron" ] ; then
    if ! _exists "crontab" ; then
      _err "It is recommended to install crontab first. try to install 'cron, crontab, crontabs or vixie-cron'."
      _err "We need to set cron job to renew the certs automatically."
      _err "Otherwise, your certs will not be able to be renewed automatically."
      if [ -z "$FORCE" ] ; then
        _err "Please add '--force' and try install again to go without crontab."
        _err "./$PROJECT_ENTRY --install --force"
        return 1
      fi
    fi
  fi
  
  if ! _exists "openssl" ; then
    _err "Please install openssl first."
    _err "We need openssl to generate keys."
    return 1
  fi
  
  if ! _exists "nc" ; then
    _err "It is recommended to install nc first, try to install 'nc' or 'netcat'."
    _err "We use nc for standalone server if you use standalone mode."
    _err "If you don't use standalone mode, just ignore this warning."
  fi
  
  return 0
}

_setShebang() {
  _file="$1"
  _shebang="$2"
  if [ -z "$_shebang" ] ; then
    _err "Usage: file shebang"
    return 1
  fi
  cp "$_file" "$_file.tmp"
  echo "$_shebang" > "$_file"
  sed -n 2,99999p  "$_file.tmp" >> "$_file"
  rm -f "$_file.tmp"  
}

_installalias() {
  _initpath

  _envfile="$STARTAPI_WORKING_DIR/$PROJECT_ENTRY.env"
  if [ "$_upgrading" ] && [ "$_upgrading" = "1" ] ; then
    echo "$(cat $_envfile)" | sed "s|^STARTAPI_WORKING_DIR.*$||" > "$_envfile"
    echo "$(cat $_envfile)" | sed "s|^alias le.*$||" > "$_envfile"
    echo "$(cat $_envfile)" | sed "s|^alias le.sh.*$||" > "$_envfile"
  fi

  _setopt "$_envfile" "export STARTAPI_WORKING_DIR" "=" "\"$STARTAPI_WORKING_DIR\""
  _setopt "$_envfile" "alias $PROJECT_ENTRY" "=" "\"$STARTAPI_WORKING_DIR/$PROJECT_ENTRY\""

  _profile="$(_detect_profile)"
  if [ "$_profile" ] ; then
    _debug "Found profile: $_profile"
    _setopt "$_profile" ". \"$_envfile\""
    _info "OK, Close and reopen your terminal to start using $PROJECT_NAME"
  else
    _info "No profile is found, you will need to go into $STARTAPI_WORKING_DIR to use $PROJECT_NAME"
  fi
  

  #for csh
  _cshfile="$STARTAPI_WORKING_DIR/$PROJECT_ENTRY.csh"
  _csh_profile="$HOME/.cshrc"
  if [ -f "$_csh_profile" ] ; then
    _setopt "$_cshfile" "setenv STARTAPI_WORKING_DIR" " " "\"$STARTAPI_WORKING_DIR\""
    _setopt "$_cshfile" "alias $PROJECT_ENTRY" " " "\"$STARTAPI_WORKING_DIR/$PROJECT_ENTRY\""
    _setopt "$_csh_profile"  "source \"$_cshfile\""
  fi
  
  #for tcsh
  _tcsh_profile="$HOME/.tcshrc"
  if [ -f "$_tcsh_profile" ] ; then
    _setopt "$_cshfile" "setenv STARTAPI_WORKING_DIR" " " "\"$STARTAPI_WORKING_DIR\""
    _setopt "$_cshfile" "alias $PROJECT_ENTRY" " " "\"$STARTAPI_WORKING_DIR/$PROJECT_ENTRY\""
    _setopt "$_tcsh_profile"  "source \"$_cshfile\""
  fi

}

# nocron
install() {
  _nocron="$1"
  if ! _initpath ; then
    _err "Install failed."
    return 1
  fi

  if [ "$_nocron" ] ; then
    _debug "Skip install cron job"
  fi
  
  if ! _precheck "$_nocron" ; then
    _err "Pre-check failed, can not install."
    return 1
  fi
  

  _info "Installing to $STARTAPI_WORKING_DIR"

  if ! mkdir -p "$STARTAPI_WORKING_DIR" ; then
    _err "Can not create working dir: $STARTAPI_WORKING_DIR"
    return 1
  fi
  
  chmod 700 "$STARTAPI_WORKING_DIR"

  cp $PROJECT_ENTRY "$STARTAPI_WORKING_DIR/" && chmod +x "$STARTAPI_WORKING_DIR/$PROJECT_ENTRY"

  if [ "$?" != "0" ] ; then
    _err "Install failed, can not copy $PROJECT_ENTRY"
    return 1
  fi

  _info "Installed to $STARTAPI_WORKING_DIR/$PROJECT_ENTRY"

  _installalias


  if [ ! -f "$ACCOUNT_CONF_PATH" ] ; then
    _initconf
  fi

  if [ "$_DEFAULT_ACCOUNT_CONF_PATH" != "$ACCOUNT_CONF_PATH" ] ; then
    _setopt "$_DEFAULT_ACCOUNT_CONF_PATH" "ACCOUNT_CONF_PATH" "=" "\"$ACCOUNT_CONF_PATH\""
  fi

  if [ "$_DEFAULT_CERT_HOME" != "$CERT_HOME" ] ; then
    _saveaccountconf "CERT_HOME" "$CERT_HOME"
  fi

  if [ "$_DEFAULT_ACCOUNT_KEY_PATH" != "$ACCOUNT_KEY_PATH" ] ; then
    _saveaccountconf "ACCOUNT_KEY_PATH" "$ACCOUNT_KEY_PATH"
  fi
  
  if [ -z "$_nocron" ] ; then
    installcronjob
  fi

  if [ -z "$NO_DETECT_SH" ] ; then
    #Modify shebang
    if _exists bash ; then
      _info "Good, bash is installed, change the shebang to use bash as prefered."
      _shebang='#!/usr/bin/env bash'
      _setShebang "$STARTAPI_WORKING_DIR/$PROJECT_ENTRY" "$_shebang"
      if [ -d "$STARTAPI_WORKING_DIR/dnsapi" ] ; then
        for _apifile in $(ls "$STARTAPI_WORKING_DIR/dnsapi/"*.sh) ; do
          _setShebang "$_apifile" "$_shebang"
        done
      fi
    fi
  fi

  _info OK
}

# nocron
uninstall() {
  _nocron="$1"
  if [ -z "$_nocron" ] ; then
    uninstallcronjob
  fi
  _initpath

  _profile="$(_detect_profile)"
  if [ "$_profile" ] ; then
    text="$(cat $_profile)"
    echo "$text" | sed "s|^.*\"$STARTAPI_WORKING_DIR/$PROJECT_NAME.env\"$||" > "$_profile"
  fi

  _csh_profile="$HOME/.cshrc"
  if [ -f "$_csh_profile" ] ; then
    text="$(cat $_csh_profile)"
    echo "$text" | sed "s|^.*\"$STARTAPI_WORKING_DIR/$PROJECT_NAME.csh\"$||" > "$_csh_profile"
  fi
  
  _tcsh_profile="$HOME/.tcshrc"
  if [ -f "$_tcsh_profile" ] ; then
    text="$(cat $_tcsh_profile)"
    echo "$text" | sed "s|^.*\"$STARTAPI_WORKING_DIR/$PROJECT_NAME.csh\"$||" > "$_tcsh_profile"
  fi
  
  rm -f $STARTAPI_WORKING_DIR/$PROJECT_ENTRY
  _info "The keys and certs are in $STARTAPI_WORKING_DIR, you can remove them by yourself."

}

cron() {
  IN_CRON=1
  renewAll
  _ret="$?"
  IN_CRON=""
  return $_ret
}

version() {
  echo "$PROJECT"
  echo "v$VER"
}

showhelp() {
  version
  echo "Usage: $PROJECT_ENTRY  command ...[parameters]....
Commands:
  --help, -h               Show this help message.
  --version, -v            Show version info.
  --install                Install $PROJECT_NAME to your system.
  --uninstall              Uninstall $PROJECT_NAME, and uninstall the cron job.
  --upgrade                Upgrade $PROJECT_NAME to the latest code from $PROJECT
  --setAPIKey 'api.p12'    Set the api key file.
  --setAPIToken 'xxxxx'    Set the api token.
  --issue                  Issue a cert.
  --installcert            Install the issued cert to apache/nginx or any other server.
  --renew, -r              Renew a cert.
  --renewAll               Renew all the certs
  --revoke                 Revoke a cert.
  --list                   List all the certs
  --installcronjob         Install the cron job to renew certs, you don't need to call this. The 'install' command can automatically install the cron job.
  --uninstallcronjob       Uninstall the cron job. The 'uninstall' command can do this automatically.
  --cron                   Run cron job to renew all the certs.
  --toPkcs                 Export the certificate and key to a pfx file.
  --createDomainKey, -cdk  Create an domain private key, professional use.
  --createCSR, -ccsr       Create CSR , professional use.
  
Parameters:
  --domain, -d   domain.tld         Specifies a domain, used to issue, renew or revoke etc.
  --force, -f                       Used to force to install or force to renew a cert immediately.
  --staging, --test                 Use staging server, just for test.
  --debug                           Output debug info.
    
  --webroot, -w  /path/to/webroot   Specifies the web root folder for web root mode.
  --standalone                      Use standalone mode.
  
  --iv                              Issue Class 2 IVSSL, you must buy the Class 2 IV validation from startssl.com
  --keylength, -k [2048]            Specifies the domain key length: 2048, 3072, 4096, 8192 or ec-256, ec-384.

  --certtype [DVSSL|IVSSL|OVSSL|EVSSL]  Certtype: DVSSL by default, IVSSL equals to '--iv'.
  
  These parameters are to install the cert to nginx/apache or anyother server after issue/renew a cert:
  
  --certpath /path/to/real/cert/file  After issue/renew, the cert will be copied to this path.
  --keypath /path/to/real/key/file  After issue/renew, the key will be copied to this path.
  --capath /path/to/real/ca/file    After issue/renew, the intermediate cert will be copied to this path.
  --fullchainpath /path/to/fullchain/file After issue/renew, the fullchain cert will be copied to this path.
  
  --reloadcmd \"service nginx reload\" After issue/renew, it's used to reload the server.

  --accountconf                     Specifies a customized account config file.
  --home                            Specifies the home dir for $PROJECT_NAME .
  --certhome                        Specifies the home dir to save all the certs, only valid for '--install' command.
  --useragent                       Specifies the user agent string. it will be saved for future use too.
  --days                            Specifies the days to renew the cert when using '--issue' command. The max value is $MAX_RENEW days.
  --httpport                        Specifies the standalone listening port. Only valid if the server is behind a reverse proxy or load balancer.
  --listraw                         Only used for '--list' command, list the certs in raw format.
  --stopRenewOnError, -se           Only valid for '--renewall' command. Stop to renew all if one cert has error in renewal.
  --nocron                          Only valid for '--install' command, which means: do not install the default cron job. In this case, the certs will not be renewed automatically.
  "
}

# nocron
_installOnline() {
  _info "Installing from online archive."
  _nocron="$1"
  if [ ! "$BRANCH" ] ; then
    BRANCH="master"
  fi
  _initpath
  target="$PROJECT/archive/$BRANCH.tar.gz"
  _info "Downloading $target"
  localname="$BRANCH.tar.gz"
  if ! _get "$target" > $localname ; then
    _debug "Download error."
    return 1
  fi
  _info "Extracting $localname"
  tar xzf $localname
  cd "$PROJECT_NAME-$BRANCH"
  chmod +x $PROJECT_ENTRY
  if ./$PROJECT_ENTRY install "$_nocron"; then
    _info "Install success!"
  fi
  
  cd ..
  rm -rf "$PROJECT_NAME-$BRANCH"
  rm -f "$localname"
}

upgrade() {
  if (
    cd $STARTAPI_WORKING_DIR
    _installOnline "nocron"
  ) ; then
    _info "Upgrade success!"
  else
    _err "Upgrade failed!"
  fi
}
 
_process() {
  _CMD=""
  _domain=""
  _altdomains="no"
  _webroot=""
  _keylength="no"
  _certpath="no"
  _keypath="no"
  _capath="no"
  _fullchainpath="no"
  _reloadcmd=""
  _password=""
  _accountconf=""
  _useragent=""
  _certhome=""
  _httpport=""
  _listraw=""
  _stopRenewOnError=""
  _apiKey=""
  _nocron=""
  _certtype=""
  while [ ${#} -gt 0 ] ; do
    case "${1}" in
    
    --help|-h)
        showhelp
        return
        ;;
    --version|-v)
        version
        return
        ;;
    --install)
        _CMD="install"
        ;;
    --uninstall)
        _CMD="uninstall"
        ;;
    --upgrade)
        _CMD="upgrade"
        ;;
    --issue)
        _CMD="issue"
        ;;
    --installcert|-i)
        _CMD="installcert"
        ;;
    --renew|-r)
        _CMD="renew"
        ;;
    --renewAll|--renewall)
        _CMD="renewAll"
        ;;
    --revoke)
        _CMD="revoke"
        ;;
    --list)
        _CMD="list"
        ;;
    --installcronjob)
        _CMD="installcronjob"
        ;;
    --uninstallcronjob)
        _CMD="uninstallcronjob"
        ;;
    --cron)
        _CMD="cron"
        ;;
    --toPkcs)
        _CMD="toPkcs"
        ;; 
    --createAccountKey|--createaccountkey|-cak)
        _CMD="createAccountKey"
        ;;
    --createDomainKey|--createdomainkey|-cdk)
        _CMD="createDomainKey"
        ;;
    --createCSR|--createcsr|-ccr)
        _CMD="createCSR"
        ;;
    --setAPIKey)
        _CMD="setAPIKey"
        _apiKey="$2"
        shift
        ;;        
    --setAPIToken)
        _CMD="setAPIToken"
        _apiToken="$2"
        shift
        ;; 
    --domain|-d)
        _dvalue="$2"
        
        if [ "$_dvalue" ] ; then
          if _startswith "$_dvalue" "-" ; then
            _err "'$_dvalue' is not a valid domain for parameter '$1'"
            return 1
          fi
          
          if [ -z "$_domain" ] ; then
            _domain="$_dvalue"
          else
            if [ "$_altdomains" = "no" ] ; then
              _altdomains="$_dvalue"
            else
              _altdomains="$_altdomains,$_dvalue"
            fi
          fi
        fi
        
        shift
        ;;

    --force|-f)
        FORCE="1"
        ;;
    --staging|--test)
        STAGE="1"
        ;;
    --iv)
        _certtype="IVSSL"
        ;;
    --debug)
        if [ -z "$2" ] || _startswith "$2" "-" ; then
          DEBUG="1"
        else
          DEBUG="$2"
          shift
        fi 
        ;;
    --webroot|-w)
        wvalue="$2"
        if [ -z "$_webroot" ] ; then
          _webroot="$wvalue"
        else
          _webroot="$_webroot,$wvalue"
        fi
        shift
        ;;        
    --standalone)
        wvalue="no"
        if [ -z "$_webroot" ] ; then
          _webroot="$wvalue"
        else
          _webroot="$_webroot,$wvalue"
        fi
        ;;
    --token)
        _token="$2"
        ACCOUNT_TOKEN="$_token"
        shift
        ;;
    --keylength|-k)
        _keylength="$2"
        accountkeylength="$2"
        shift
        ;;
    --certpath)
        _certpath="$2"
        shift
        ;;
    --keypath)
        _keypath="$2"
        shift
        ;;
    --capath)
        _capath="$2"
        shift
        ;;
    --fullchainpath)
        _fullchainpath="$2"
        shift
        ;;
    --reloadcmd|--reloadCmd)
        _reloadcmd="$2"
        shift
        ;;
    --password)
        _password="$2"
        shift
        ;;
    --accountconf)
        _accountconf="$2"
        ACCOUNT_CONF_PATH="$_accountconf"
        shift
        ;;
    --home)
        STARTAPI_WORKING_DIR="$2"
        shift
        ;;
    --certhome)
        _certhome="$2"
        CERT_HOME="$_certhome"
        shift
        ;;        
    --useragent)
        _useragent="$2"
        USER_AGENT="$_useragent"
        shift
        ;;
    --accountkey )
        _accountkey="$2"
        ACCOUNT_KEY_PATH="$_accountkey"
        shift
        ;;
    --days )
        _days="$2"
        Le_RenewalDays="$_days"
        shift
        ;;
    --httpport )
        _httpport="$2"
        Le_HTTPPort="$_httpport"
        shift
        ;;
        
    --listraw )
        _listraw="raw"
        ;;        
    --stopRenewOnError|--stoprenewonerror|-se )
        _stopRenewOnError="1"
        ;;
    --nocron)
        _nocron="1"
        ;;
    *)
        _err "Unknown parameter : $1"
        return 1
        ;;
    esac

    shift 1
  done


  case "${_CMD}" in
    install) install "$_nocron" ;;
    uninstall) uninstall "$_nocron" ;;
    upgrade) upgrade ;;
    issue)
      issue  "$_webroot"  "$_domain" "$_altdomains" "$_keylength" "$_certpath" "$_keypath" "$_capath" "$_reloadcmd" "$_fullchainpath" "$_certtype"
      ;;
    installcert)
      installcert "$_domain" "$_certpath" "$_keypath" "$_capath" "$_reloadcmd" "$_fullchainpath"
      ;;
    renew) 
      renew "$_domain" 
      ;;
    renewAll) 
      renewAll "$_stopRenewOnError"
      ;;
    revoke) 
      revoke "$_domain" 
      ;;
    list) 
      list "$_listraw"
      ;;
    installcronjob) installcronjob ;;
    uninstallcronjob) uninstallcronjob ;;
    cron) cron ;;
    toPkcs) 
      toPkcs "$_domain" "$_password"
      ;;
    createDomainKey) 
      createDomainKey "$_domain" "$_keylength"
      ;;
    createCSR) 
      createCSR "$_domain" "$_altdomains"
      ;;
    setAPIKey) 
      setAPIKey "$_apiKey" "$_password"
      ;;
    setAPIToken) 
      setAPIToken "$_apiToken"
      ;;      
    *)
      _err "Invalid command: $_CMD"
      showhelp;
      return 1
    ;;
  esac
  _ret="$?"
  if [ "$_ret" != "0" ] ; then
    return $_ret
  fi
  
  if [ "$_useragent" ] ; then
    _saveaccountconf "USER_AGENT" "$_useragent"
  fi
 

}


if [ "$INSTALLONLINE" ] ; then
  INSTALLONLINE=""
  _installOnline $BRANCH
  exit
fi

if [ -z "$1" ] ; then
  showhelp
else
  if echo "$1" | grep "^-" >/dev/null 2>&1 ; then
    _process "$@"
  else
    "$@"
  fi
fi


