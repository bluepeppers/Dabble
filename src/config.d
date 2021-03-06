private {
    import std.path;
    import std.file;
    import std.stdio;
    import std.array : split, join;
    import std.datetime;
    
    import ini;
    import mod;
    import color;
}

IniData conf;
SysTime conf_written;

bool dot_dabble_exists(string root) {
    auto dabblef = buildNormalizedPath(root, ".dabble");
    return exists(dabblef) && isDir(dabblef);
}

void init_dot_dabble(string root) {
    string dabblef = buildNormalizedPath(root, ".dabble");
    mkdir(dabblef);
    mkdir(buildNormalizedPath(dabblef, "modules"));
}

bool dabble_conf_exists(string root) {
    auto dabblef = buildNormalizedPath(root, ".dabble.conf");
    return exists(dabblef) && isFile(dabblef);
}
void init_dabble_conf(string root) {
    IniData conf;
    conf["core"]["name"] = baseName(root);

    conf["build.default"]["compile_flags"] = "-inline";
    conf["build.default"]["link_flags"] = "-inline";
    conf["build.release"]["compile_flags"] = "-inline -release -O";
    conf["build.release"]["link_flags"] = "-inline -release -O";
    conf["build.debug"]["compile_flags"] = "-debug -g";
    conf["build.debug"]["link_flags"] = "-debug -g";
    conf["build.unittest"]["compile_flags"] = "-unittest -g";
    conf["build.unittest"]["link_flags"] = "-unittest -g";
    write_ini(conf, buildNormalizedPath(root, ".dabble.conf"));
}

IniData get_dabble_conf(string root) {
    return read_ini(buildNormalizedPath(root, ".dabble.conf"));
}

void write_dabble_conf() {
    auto pth = buildNormalizedPath(get(conf, "internal", "root_dir"), ".dabble.conf");
    conf.remove("internal");
    write_ini(conf, pth);
}

bool bin_exists() {
    auto bin = buildNormalizedPath(conf["internal"]["root_dir"], "bin");
    return exists(bin) && isDir(bin);
}

string binary_location(Module mod) {
    string binname = mod.package_name;
    string bt = conf["internal"]["build_type"];
    
    // Special case #1
    if (bt ~ "_targets" in conf && binname in conf[bt ~ "_targets"])
        binname = get(conf, bt ~ "_targets", binname);
    else {
        if (binname == "main")
            binname = get(conf, "core", "name", binname);
        if (bt != "default")
            binname ~= "." ~ conf["internal"]["build_type"];
    }
        
    auto pth = buildNormalizedPath(conf["internal"]["root_dir"], "bin", binname);
    return pth;
}

string library_location(Module mod) {
    string bt = conf["internal"]["build_type"];
    auto libname = mod.package_name;
    if (get(conf, bt ~ "_targets", mod.package_name) != "")
        libname = get(conf, bt ~ "_targets", mod.package_name);
    else if (bt != "default")
        libname ~= "." ~ bt;
    return buildNormalizedPath(conf["internal"]["root_dir"], "lib",
                               libname ~ ".a");
}

void init_bin() {
    auto bin = buildNormalizedPath(conf["internal"]["root_dir"], "bin");
    mkdir(bin);
}

bool pkg_exists() {
    auto pkg = buildNormalizedPath(conf["internal"]["root_dir"], "pkg");
    auto obj = buildNormalizedPath(pkg, conf["internal"]["build_type"]);
    return exists(pkg) && isDir(pkg) && exists(obj) && isDir(obj);
}

void init_pkg() {
    auto pkg = buildNormalizedPath(conf["internal"]["root_dir"], "pkg");
    try
        mkdir(pkg);
    catch (FileException)
        mkdir(buildNormalizedPath(pkg, conf["internal"]["build_type"]));
}
bool lib_exists() {
    auto lib = buildNormalizedPath(conf["internal"]["root_dir"], "lib");
    return exists(lib) && isDir(lib);
}

void init_lib() {
    auto lib = buildNormalizedPath(conf["internal"]["root_dir"], "lib");
    mkdir(lib);
}

string object_dir() {
    return buildNormalizedPath(conf["internal"]["root_dir"], "pkg",
                               conf["internal"]["build_type"]);
}

string object_file(Module mod) {
    string split_pkg = buildNormalizedPath(join(split(mod.package_name, "."), "/"));
    string path = buildNormalizedPath(object_dir(),
                                      split_pkg ~ ".o");
    return path;
}

string get_user_compile_flags() {
    return get(conf, "build." ~ conf["internal"]["build_type"], "compile_flags");
}

string get_user_link_flags() {
    return get(conf, "build." ~ conf["internal"]["build_type"], "link_flags");
}

void load_config() {
    string root_dir = find_root_dir();
    bool root_found = root_dir != "";

    if (!root_found) {
        root_dir = guess_root_dir();
        root_dir = verify_root_dir(root_dir);
    }
    if (!dot_dabble_exists(root_dir)) {
        init_dot_dabble(root_dir);
    }
    if (!dabble_conf_exists(root_dir)) {
        init_dabble_conf(root_dir);
    }
    conf = get_dabble_conf(root_dir);
    conf_written = timeLastModified(buildPath(root_dir, ".dabble.conf"));
    
    string src_dir;
    if (get(conf, "core", "src_dir") == "") {
        src_dir = find_src_dir(root_dir);
        conf["core"]["src_dir"] = relativePath(src_dir, root_dir);
        write_dabble_conf();
    } else
        src_dir = buildNormalizedPath(absolutePath(get(conf, "core", "src_dir"), root_dir));
    
    conf["internal"]["src_dir"] = src_dir;
    conf["internal"]["root_dir"] = root_dir;
    conf["internal"]["build_type"] = "default";
}

string find_root_dir() {
    string find_root_prime(string checking) {
        if (checking == "/")
            return "";
        if (exists(buildNormalizedPath(checking, ".dabble")) &&
            isDir(buildNormalizedPath(checking, ".dabble")) ||
            exists(buildNormalizedPath(checking, ".dabble.conf")) &&
            isFile(buildNormalizedPath(checking, ".dabble.conf")))
            return checking;
        else
            return find_root_prime(buildNormalizedPath(checking, ".."));
    }
    return absolutePath(find_root_prime(getcwd()));
}

string guess_root_dir() {
    int[string] grade_roots(string checking, int[string] grades) {
        if (checking == "/")
            return grades;

        int score = 0;
        // check for src dir
        string src_path = buildNormalizedPath(checking, "src");
        if (exists(src_path) && isDir(src_path))
            score += 10;
        else {
            // Check for project dir (common to have src in there) 
            src_path = buildNormalizedPath(checking, baseName(checking));
            if (exists(src_path) && isDir(src_path))
                score += 5;
            src_path = checking;
        }
        auto src_files = dirEntries(src_path, SpanMode.shallow);
        foreach(string filename; src_files) {
            if (extension(filename) == ".d")
                score++;
        }
        grades[checking] = score;
        return grade_roots(buildNormalizedPath(checking, ".."), grades);
    }
    auto max_grade = -1;
    auto max_name = "";
    foreach(name, grade; grade_roots(getcwd, ["": -1])) {
        if (grade > max_grade) {
            max_grade = grade;
            max_name = name;
        }
    }
    return absolutePath(max_name);
}

string verify_root_dir(string root) {
    write("No Dabble directories found, predicted project root at ",
          relativePath(root, getcwd()), " Ok? [Y/n] ");
    auto response = readln();
    if (response[0..1] == "n") {
        write("Please enter the project root: ");
        root = strip(readln());
        while (!isValidPath(root)) {
            write("Invalid path, please try again: ");
            root = strip(readln());
        }
    }
    writeln("Project root at ", relativePath(root, getcwd()));
    return absolutePath(root);
}

string find_src_dir(string root) {
    auto src = buildNormalizedPath(root, "src");
    if (exists(src) && isDir(src))
        return src;
    else
        return root;
}

bool parse_args(string[] args) {
    if (args.length < 2)
        return true;

    string compile_flags, link_flags;
    
    auto len = args.length;
    for(int i = 1; i < len; i++) {
        string arg = args[i];

        switch(arg) {
        case "-v", "--verbose":
            debug writeln("Verbose");
            conf["ui"]["verbose"] = "yes";
            break;
        case "-q", "--quiet":
            debug writeln("Quiet");
            conf["ui"]["verbose"] = "";
            break;
        case "-c", "--compile-flags":
            debug writeln("Compile flags: ", args[i+1]);
            // These depend on build_type, so must be parsed later.
            // However, their positional arguments must still be consumed
            compile_flags = args[++i];
            break;
        case "-l", "--link-flags":
            debug writeln("Link flags: ", args[i+1]);
            link_flags = args[++i];
            break;
        default:
            if (conf["internal"]["build_type"] == "default") {
                if ("build." ~ arg !in conf) {
                    writelnc("No build config named " ~ arg, COLORS.red);
                    return false;
                }
                conf["internal"]["build_type"] = arg;
                debug writeln("BT: ", arg);
            }
        }
    }
    auto bt = conf["internal"]["build_type"];
    conf[bt]["compile_flags"] = compile_flags;
    conf[bt]["link_flags"] = link_flags;
    
    return true;
}