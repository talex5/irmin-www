irmin-www
=========

Copyright Thomas Leonard, 2015

A basic **experimental** web-server that can be deployed as a Mirage unikernel.
It serves pages directly from an in-memory Irmin repository.


Instructions
------------

Configure using mirage as usual (use `--xen` for a unikernel or `--unix` to make a regular Unix server process):

    opam install mirage
    env DHCP=yes mirage configure --xen

Generate a private key and X.509 certificate:

    $ make conf/tls/server.pem

For testing, you can accept the defaults for most fields, but make sure you enter the server's name as the "Common Name":

    Common Name (e.g. server FQDN or YOUR name) []:www.example.org

This will create a private key (`conf/tls/server.key`) and a self-signed certificate (`conf/tls/server.pem`). You can replace the self-signed X.509 certificate with a certified one from a CA if desired.

    make

It will serve web pages on port 8443 and accept Irmin operations on port 8444.
To view the site, visit:

    https://www.example.org:8443/

If you're using a self-signed certificate, your brower should prompt you to confirm you trust it now.

To replace the default page:

    irmin write -s http --uri https://www.example.org:8444 index.html '<h1>Hello, world!</h1>'

Currently:

- There is no access control. Anyone can manipulate the site via the Irmin API.


Conditions
----------

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
