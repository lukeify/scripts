#!/usr/bin/env bash

nginx_version=$(nginx -v 2>&1 | awk -F'/' '{print $2}')

echo "Downloading nginx $nginx_version from nginx.org..."
wget "https://nginx.org/download/nginx-$nginx_version.tar.gz"
tar -xf "nginx-$nginx_version.tar.gz"

# Follow the "Statically compiled" steps from `google/ngx_brotli`
# https://github.com/google/ngx_brotli#statically-compiled
git clone --recurse-submodules -j8 https://github.com/google/ngx_brotli
cd ngx_brotli/deps/brotli || exit
mkdir out && cd out || exit
cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_C_FLAGS="-Ofast -m64 -march=native -mtune=native -flto -funroll-loops -ffunction-sections -fdata-sections -Wl,--gc-sections" -DCMAKE_CXX_FLAGS="-Ofast -m64 -march=native -mtune=native -flto -funroll-loops -ffunction-sections -fdata-sections -Wl,--gc-sections" -DCMAKE_INSTALL_PREFIX=./installed ..
cmake --build . --config Release --target brotlienc

# Now, follow the "Dynamically loaded" steps.
# https://github.com/google/ngx_brotli?tab=readme-ov-file#dynamically-loaded
cd "../../../../nginx-$nginx_version" || exit
nginx_args=$(nginx -V 2>&1 | awk -F'configure arguments: ' '/configure arguments:/ {print $2}')
./configure "$nginx_args" --with-compat --add-dynamic-module=../ngx_brotli

# Move the compiled object files. This must be run as sudo.
mv objs/*.so /usr/lib/nginx/modules

# Introduce the `load_module` directives into `nginx.conf`. This also requires sudo.
add_before_http="
load_module modules/ngx_http_brotli_filter_module.so;
load_module modules/ngx_http_brotli_static_module.so;
"

# Check if the modules are already present in the file
if ! grep -q 'ngx_http_brotli_filter_module.so' /etc/nginx/nginx.conf && \
  ! grep -q 'ngx_http_brotli_static_module.so' /etc/nginx/nginx.conf; then
  awk -i inplace '
  BEGIN {
    add_before_http="'"$add_before_http"'"
  }
  /^http {/{
    print add_before_http
  }
  {
    print
  }
  ' /etc/nginx/nginx.conf
  echo "Modules added to nginx.conf"
else
  echo "Modules already present in nginx.conf"
fi

# Cleanup
cd "../" || exit
rm "nginx-$nginx_version.tar.gz"
rm -r "nginx-$nginx_version"
rm -r ngx_brotli
