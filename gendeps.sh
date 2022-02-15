#!/bin/bash

set -e
# set -x

# This script generates Flatpak sources for a gradle project.

# It works by running the gradle build (--dry-run is usually enough) with
# a separate, new gradle user home (instead of ~/.gradle). All needed
# dependencies will be cached in this gradle user home. The script then moves
# all these cached artifacts into a directory structure of a maven repo.
# It also computes the hashes and checks the repos for where this artifact is
# available to generate the url.
# Finally, it writes the json file which can be used in the flatpak build
# manifest.

# You may want to modify these variables
# Where the sources json file should be generated:
SOURCES_FILE="../gradle-sources.json"
# The target to generate the dependencies for:
TARGET="desktop:dist"
# The maven repos:
REPO_BASEURL=(
	'https://repo1.maven.org/maven2/'
	'https://jitpack.io/'
	'https://plugins.gradle.org/m2/'
)
# Manually specify dependencies that aren't getting cached for some reason:
MANUAL_ARTIFACTS=(
	'com/github/Anuken/Arc/backend-headless/916c5a77/backend-headless-916c5a77.pom'
	'com/github/Anuken/Arc/backend-headless/916c5a77/backend-headless-916c5a77.jar'
)


# These directories should be empty and will get `rm -r`d afterwards.
gradle_user_home="$(mktemp -d)"
maven_repo="$(mktemp -d)"

wd="$(pwd)"

# Let gradle fetch all the dependencies into a new clean gradle user home:
echo "Downloading all dependencies..."
./gradlew -g "$gradle_user_home" "$TARGET" --no-daemon -q
# --dry-run seems to miss some dependendencies
# ./gradlew -g "$gradle_user_home" "$TARGET" --no-daemon --dry-run -q


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
# And close the json array
echo ']' >> "$json_file"

# Clean up maven repo too
cd "$wd"
rm -r "$maven_repo"

echo 'Finished. Success is unknown until observed.'
