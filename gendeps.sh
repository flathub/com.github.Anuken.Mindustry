#!/bin/bash

set -e
# set -x

# Modify if needed
SOURCES_FILE="../gradle-sources.json"
TARGET="desktop:dist"
REPO_BASEURL=(
	'https://repo1.maven.org/maven2/'
	'https://jitpack.io/'
	'https://plugins.gradle.org/m2/'
)
MANUAL_ARTIFACTS=(
	'asm/asm-parent/3.3.1/asm-parent-3.3.1.pom'
	'asm/asm/3.3.1/asm-3.3.1.pom'
	'asm/asm/3.3.1/asm-3.3.1.jar'
	'com/github/Anuken/Arc/backend-headless/916c5a77/backend-headless-916c5a77.pom'
	'com/github/Anuken/Arc/backend-headless/916c5a77/backend-headless-916c5a77.jar'
	'com/google/code/findbugs/jsr305/3.0.2/jsr305-3.0.2.pom'
	'com/google/code/findbugs/jsr305/3.0.2/jsr305-3.0.2.jar'
	'org/apache/apache/4/apache-4.pom'
	'org/apache/apache/7/apache-7.pom'
	'org/apache/apache/9/apache-9.pom'
	'org/apache/apache/10/apache-10.pom'
	'org/apache/apache/13/apache-13.pom'
	'org/apache/commons/commons-parent/22/commons-parent-22.pom'
	'org/apache/maven/maven-parent/21/maven-parent-21.pom'
	'org/apache/maven/maven-parent/23/maven-parent-23.pom'
	'org/codehaus/plexus/plexus-component-annotations/1.5.5/plexus-component-annotations-1.5.5.pom'
	'org/codehaus/plexus/plexus-component-annotations/1.5.5/plexus-component-annotations-1.5.5.jar'
	'org/codehaus/plexus/plexus-components/1.1.18/plexus-components-1.1.18.pom'
	'org/codehaus/plexus/plexus-containers/1.5.5/plexus-containers-1.5.5.pom'
	'org/codehaus/plexus/plexus-interpolation/1.14/plexus-interpolation-1.14.pom'
	'org/codehaus/plexus/plexus-interpolation/1.14/plexus-interpolation-1.14.jar'
	'org/codehaus/plexus/plexus-utils/3.0.8/plexus-utils-3.0.8.pom'
	'org/codehaus/plexus/plexus-utils/3.0.8/plexus-utils-3.0.8.jar'
	'org/codehaus/plexus/plexus/2.0.7/plexus-2.0.7.pom'
	'org/codehaus/plexus/plexus/3.2/plexus-3.2.pom'
	'org/sonatype/forge/forge-parent/10/forge-parent-10.pom'
	'org/sonatype/oss/oss-parent/7/oss-parent-7.pom'
	'org/sonatype/oss/oss-parent/9/oss-parent-9.pom'
	'org/sonatype/spice/spice-parent/17/spice-parent-17.pom'
)

gradle_user_home="$(mktemp -d)"
maven_repo="$(mktemp -d)"
wd="$(pwd)"

# Let gradle fetch all the dependencies into a new clean gradle user home:
echo "Downloading all dependencies..."
# INFO: Using system gradle to avoid redownloading the wrapper every time
# gradle -g "$gradle_user_home" "$TARGET" --no-daemon --dry-run > /dev/null
gradle -g "$gradle_user_home" "$TARGET" --no-daemon


cd "$gradle_user_home/caches/modules-2/files-2.1" || exit 1

# Following two blocks are adapted from here:
# https://gist.github.com/danieldietrich/76e480f3fb903bdeaac5b1fb007ab5ac
# Thank you Daniel Dietrich!

# Transforms gradle cache paths to maven repo paths
function mavenize {
	IFS='/' read -r -a paths <<< "$1"
	groupId=$(echo "${paths[1]}" | tr . /)
	artifactId="${paths[2]}"
	version="${paths[3]}"
	echo "$groupId/$artifactId/$version"
}

# Copy every file from the cache to it's maven repo location
find . -type f -print0 | while IFS= read -r -d '' file; do
	filename=$(basename "$file")
	source_dir=$(dirname "$file")
	target_dir="$maven_repo/$(mavenize "$file")"
	mkdir -p "$target_dir" && cp "$source_dir/$filename" "$target_dir/"
done

# All interesting files are now in the maven repo
cd "$wd"
rm -r "$gradle_user_home"
# echo "Gradle user home: $gradle_user_home"

# Create the json sources file
cd "$maven_repo"

json_file="$wd/$SOURCES_FILE"
echo '[' > "$json_file"

# Download the $MANUAL_ARTIFACTS manually
for dep in "${MANUAL_ARTIFACTS[@]}"; do
	mkdir -p "$(dirname "$dep")"

	success=0
	for repo in "${REPO_BASEURL[@]}"; do
		url="${repo}${dep}"
		if curl "$url" --fail --output "$dep" -L &> /dev/null; then
			success=1
			break
		fi
	done
	if [ $success -eq 0 ]; then
		echo "ERROR: No repo contains manual dependency $dep"
		exit 1
	fi
done

# `find *` to not use the ./ prefix when appending to $REPO_BASEURL
# shellcheck disable=SC2035
find * -type f -print0 | while IFS= read -r -d '' file; do
	# Every repo if the ressource exists there
	url=''
	for repo in "${REPO_BASEURL[@]}"; do
		url_to_try="${repo}${file}"
		if curl --HEAD "$url_to_try" --fail -L &> /dev/null; then
			url="$url_to_try"
			break
		fi
	done
	if [ -z "$url" ]; then
		echo "ERROR: No repo contains $file"
		exit 1
	fi

	hash="$(sha256sum "$file" | cut -f 1 -d ' ')"
	cat << HERE >> "$json_file"
	{
		"type": "file",
		"url": "$url",
		"sha256": "$hash",
		"dest": "maven-local/$(dirname "$file")",
		"dest-filename": "$(basename "$file")"
	},
HERE
done


# Remove last line in json file and relpace with closing braces without comma
head -n -1 "$json_file" > temp.json && mv temp.json "$json_file"
echo '	}' >> "$json_file"
# And close the json
echo ']' >> "$json_file"

# Clean up maven repo too
cd "$wd"
rm -r "$maven_repo"
# echo "Maven repo: $maven_repo"

