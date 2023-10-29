#!/bin/bash

ARCH="aarch64" # x86_64, aarch64
os="mac" # linux, mac
mac_m1_workaround=true

BUILDTOOLS_DOWNLOAD="https://hub.spigotmc.org/jenkins/job/BuildTools/lastSuccessfulBuild/artifact/target/BuildTools.jar"

wget -O BuildTools.jar "$BUILDTOOLS_DOWNLOAD"

# Download Java
JAVA_VERSIONS=$(cat mapping.csv | cut -d';' -f2 | uniq | tr '\n' ' ')
echo "Downloading java versions $JAVA_VERSIONS"

for javaVersion in $JAVA_VERSIONS; do
  echo "Checking if java version $javaVersion is available"
  out=$(curl -s "https://api.adoptium.net/v3/info/available_releases" | jq -e ".available_releases[] | select(. == $javaVersion)")
  if [ $? -ne 0 ] || [ "$out" == "" ]; then
    echo $out
    echo "Error: Java version $javaVersion is not available." >&2
    exit 1
  fi
done

for javaVersion in $JAVA_VERSIONS; do
  arch=$ARCH
  if [ $mac_m1_workaround == "true" ] && [ "$javaVersion" == "8" ]; then
    arch="x64"
  fi
  # Get Release name
  prev=$(((javaVersion - 1)))
  next=$(((javaVersion + 1)))
  release=$(curl -X 'GET' \
               "https://api.adoptium.net/v3/info/release_names?architecture=$arch&heap_size=normal&image_type=jdk&jvm_impl=hotspot&os=$os&page=0&page_size=10&project=jdk&release_type=ga&semver=false&sort_method=DEFAULT&sort_order=DESC&vendor=eclipse&version=%28$prev%2C$next%5D" \
               -H 'accept: application/json' | jq -r '.releases[0]')
  if [ -z "$release" ]; then
    echo "Error: Release name for $javaVersion is empty." >&2
    exit 1
  fi
  echo "Release name for $javaVersion is $release"

  echo "Downloading java version $javaVersion for arch $arch"
  filename=$(wget --server-response -q -O - "https://api.adoptium.net/v3/binary/latest/$javaVersion/ga/$os/$arch/jdk/hotspot/normal/eclipse?project=jdk" 2>&1 |
    grep "Content-Disposition:" | tail -1 | cut -d ';' -f2 | sed 's/filename=//g' | tr -d '\r')
  echo "Downloading $filename"
  if ! [ -f "$filename" ]; then
    echo "Download"
    wget -O "$filename" "https://api.adoptium.net/v3/binary/latest/$javaVersion/ga/$os/$arch/jdk/hotspot/normal/eclipse?project=jdk"
    # Remove spaces from filename
    mv "$filename" $(echo "$filename" | tr -d ' ')
    filename=$(echo "$filename" | tr -d ' ')
  fi

  tar -xzf "$filename"

  JAVA_DIR[$javaVersion]=$(tar -ztf $filename | head -1)
  echo "Java dir for $javaVersion is ${JAVA_DIR[$javaVersion]}"
done

# Iterate over mapping.csv
for mapping in $(cat mapping.csv); do
  echo "Processing $mapping"
  sleep 1
  ver=$(echo "$mapping" | cut -d';' -f1)
  javaVersion=$(echo "$mapping" | cut -d';' -f2)
  javaBin=${JAVA_DIR[$javaVersion]}bin/java
  if [ $os == "mac" ]; then
    javaBin=${JAVA_DIR[$javaVersion]}Contents/Home/bin/java
  fi
  chmod +x "$javaBin"

  javaBin=../$javaBin # Further down we cd into $ver

  if [ $mac_m1_workaround == "true" ] && [ "$javaVersion" == "8" ]; then
      javaBin="arch -x86_64 $javaBin"
  fi

  mkdir -p "$ver"
  cp BuildTools.jar "$ver"
  cd "$ver"

  $javaBin -jar BuildTools.jar --output-dir "$ver" --rev "$ver"
  filepath="spigot-$ver.jar"

  mvn deploy:deploy-file -DgroupId=org.spigotmc-test \
      -DartifactId=spigot \
      -Dversion="$ver" \
      -Dpackaging=jar \
      -Dfile="$ver/$filepath" \
      -DrepositoryId=lyrotopia-group \
      -Durl=https://nexus.lyrotopia.net/repository/maven-releases

  cd ..
done
