# Mindustry flatpak

## Generator help
The `gendeps.sh` script can (for the most part) automatically generate the
gradle-sources.json file.

### How to use
1. Adjust the `$SOURCES_FILE` variable to where you want the json file to be
   generated.
2. Clone the [Mindustry repo](https://github.com/Anuken/Mindustry) and cd into it.
3. Run the `gendeps.sh` script from there.

### The dependency `com.github.Anuken.Arc:backend-headless:???` isn't found
For some reason, the script doesn't automatically recognize the dependency on
com.github.Anuken.Arc:backend-headless. Thus it is manually added in the generator
script. Whenever the required version changes, the version written in the
generator needs to be adjusted (the failed gradle build will tell you the
expected version).

### Many dependencies are missing
Make sure gradle won't pull any dependencies from `mavenLocal` (`~/.m2/`).
Either remove the `mavenLocal()` source from the `build.gradle` or delete
`~/.m2/`.

If you need more help, ping [@TobTobXX](https://github.com/TobTobXX).

