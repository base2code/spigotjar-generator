#!/bin/bash

arch="x64"
os="linux"

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
  ver=$(echo "$mapping" | cut -d';' -f1)
  javaVersion=$(echo "$mapping" | cut -d';' -f2)
  javaBin=${JAVA_DIR[$javaVersion]}bin/java

  $javaBin -jar BuildTools.jar --rev "$ver"
  filepath="spigot-$ver.jar"

  mvn deploy:deploy-file -DgroupId=org.spigotmc-test \
    -DartifactId=spigot \
    -Dversion="$ver"> \
    -Dpackaging=jar \
    -Dfile="$filepath" \
    -DrepositoryId=maven-releases \
    -Durl=https://nexus.lyrotopia.net/repository/maven-releases
done
