// Operation: absolute project path and relative component import -> normalized source/output paths.
import std.mem;
import { dirname } from std.path;

fn append(out: &List<u8>, text: string): void {
    for byte in text.bytes() {
        out.push(byte);
    }
}

pub enum PathError {
    relative_root;
    outside_root;
    invalid_import;
}

fn separator(byte: u8): bool {
    return byte == 47 or byte == 92;
}

pub fn absolute(path: string): bool {
    const bytes = path.bytes();
    if bytes.len() == 0 {
        return false;
    }
    if bytes[0] == 47 {
        return true;
    }
    return bytes.len() >= 3 and
        ((bytes[0] >= 65 and bytes[0] <= 90) or (bytes[0] >= 97 and bytes[0] <= 122)) and
        bytes[1] == 58 and separator(bytes[2]);
}

pub fn normalize(path: string): string ! PathError {
    const bytes = path.bytes();
    if not absolute(path) {
        throw PathError.relative_root;
    }
    const drive = bytes[0] != 47;
    var parts = list<string>();
    var start: usize = 1;
    if drive {
        start = 3;
    }
    var i: usize = start;
    while i <= bytes.len() {
        if i == bytes.len() or separator(bytes[i]) {
            if i > start {
                const part = string.from(bytes[start..i]);
                if part == ".." {
                    if parts.len() == 0 {
                        throw PathError.outside_root;
                    }
                    const _ = parts.pop();
                } else if part != "." {
                    parts.push(part);
                }
            }
            start = i + 1;
        }
        i = i + 1;
    }
    var out = list<u8>();
    if drive {
        out.push(bytes[0]);
        append(&out, ":/");
    } else {
        append(&out, "/");
    }
    i = 0;
    while i < parts.len() {
        if i > 0 {
            append(&out, "/");
        }
        append(&out, parts[i]);
        i = i + 1;
    }
    return string.from(out.view());
}

pub fn component(importer: string, specifier: string): string ! PathError {
    const bytes = specifier.bytes();
    if not mem.starts_with(bytes, "./".bytes()) and not mem.starts_with(bytes, "../".bytes()) {
        throw PathError.invalid_import;
    }
    if not mem.ends_with(bytes, ".weiv".bytes()) {
        throw PathError.invalid_import;
    }
    const parent = dirname(importer);
    return try normalize($"{parent}/{specifier}");
}

pub fn module_path(root: string, source_path: string): string ! PathError {
    const relative = try output_path(root, source_path);
    if not mem.ends_with(relative.bytes(), ".weiv".bytes()) {
        throw PathError.invalid_import;
    }
    const bytes = relative.bytes();
    const stem = string.from(bytes[..bytes.len() - 5]);
    return $"{stem}.mjs";
}

pub fn output_path(root: string, source_path: string): string ! PathError {
    const normalized_root = try normalize(root);
    const normalized_source = try normalize(source_path);
    const root_bytes = normalized_root.bytes();
    const source_bytes = normalized_source.bytes();
    if source_bytes.len() <= root_bytes.len() or not mem.starts_with(source_bytes, root_bytes) or source_bytes[root_bytes.len()] != 47 {
        throw PathError.outside_root;
    }
    const relative = source_bytes[root_bytes.len() + 1..];
    return string.from(relative);
}
