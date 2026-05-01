use oxc_ast::ast::{
    BindingPattern, Declaration, ImportDeclarationSpecifier, ImportOrExportKind, Statement,
    VariableDeclarationKind,
};
use oxc_allocator::Allocator;
use oxc_codegen::{Codegen, CodegenOptions};
use oxc_parser::Parser;
use oxc_semantic::SemanticBuilder;
use oxc_span::SourceType;
use oxc_transformer::{TransformOptions, Transformer};
use serde::Serialize;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::Path;

#[derive(Serialize)]
struct ScriptAnalysisResponse {
    ok: bool,
    source_path: String,
    transpiled_code: String,
    props: Option<PropsRecord>,
    imports: Vec<ImportRecord>,
    bindings: Vec<BindingRecord>,
    diagnostics: Vec<DiagnosticRecord>,
}

#[derive(Serialize, Default)]
struct PropsRecord {
    has_props_export: bool,
    props_binding_name: Option<String>,
    props_type_name: Option<String>,
}

#[derive(Serialize)]
struct ImportRecord {
    source: String,
    kind: String,
    imported_name: Option<String>,
    local_name: String,
    span_start: usize,
    span_end: usize,
}

#[derive(Serialize)]
struct BindingRecord {
    name: String,
    kind: String,
    exported: bool,
    template_visible: bool,
    callable: bool,
    type_annotation: Option<String>,
    span_start: usize,
    span_end: usize,
}

#[derive(Serialize)]
struct DiagnosticRecord {
    severity: String,
    message: String,
    span_start: usize,
    span_end: usize,
    line: u32,
    column: u32,
    code: Option<String>,
}

#[no_mangle]
pub extern "C" fn weiv_script_analyze(
    source: *const c_char,
    source_path: *const c_char,
) -> *mut c_char {
    let source = match parse_required_cstr(source) {
        Some(value) => value,
        None => return std::ptr::null_mut(),
    };
    let source_path = parse_optional_cstr(source_path).unwrap_or_else(|| "<script>".to_string());

    let source_type = SourceType::from_path(&source_path).unwrap_or(SourceType::ts());
    let allocator = Allocator::default();
    let parsed = Parser::new(&allocator, &source, source_type).parse();

    if !parsed.errors.is_empty() {
        let diagnostics = parsed
            .errors
            .iter()
            .map(|error| DiagnosticRecord {
                severity: "error".to_string(),
                message: error.to_string(),
                span_start: 0,
                span_end: 0,
                line: 0,
                column: 0,
                code: None,
            })
            .collect();

        let response = ScriptAnalysisResponse {
            ok: false,
            source_path,
            transpiled_code: String::new(),
            props: None,
            imports: Vec::new(),
            bindings: Vec::new(),
            diagnostics,
        };

        return to_json_ptr(&response);
    }

    let transpiled_code = transpile_source(&source, &source_path).unwrap_or_default();

    let mut response = ScriptAnalysisResponse {
        ok: true,
        source_path,
        transpiled_code,
        props: Some(PropsRecord::default()),
        imports: Vec::new(),
        bindings: Vec::new(),
        diagnostics: Vec::new(),
    };

    for statement in &parsed.program.body {
        match statement {
            Statement::ImportDeclaration(decl) => {
                let source_name = decl.source.value.as_str().to_string();
                let declaration_is_type_only = decl.import_kind == ImportOrExportKind::Type;
                match &decl.specifiers {
                    None => response.imports.push(ImportRecord {
                        source: source_name,
                        kind: "side_effect".to_string(),
                        imported_name: None,
                        local_name: String::new(),
                        span_start: decl.span.start as usize,
                        span_end: decl.span.end as usize,
                    }),
                    Some(specifiers) => {
                        for specifier in specifiers {
                            match specifier {
                                ImportDeclarationSpecifier::ImportSpecifier(spec) => {
                                    let is_type_only =
                                        declaration_is_type_only || spec.import_kind == ImportOrExportKind::Type;
                                    let local_name = spec.local.name.as_str().to_string();
                                    response.imports.push(ImportRecord {
                                        source: source_name.clone(),
                                        kind: if is_type_only {
                                            "named".to_string()
                                        } else {
                                            "named".to_string()
                                        },
                                        imported_name: Some(module_export_name(&spec.imported)),
                                        local_name: local_name.clone(),
                                        span_start: decl.span.start as usize,
                                        span_end: decl.span.end as usize,
                                    });
                                    response.bindings.push(BindingRecord {
                                        name: local_name,
                                        kind: if is_type_only {
                                            "type_only".to_string()
                                        } else {
                                            "import".to_string()
                                        },
                                        exported: false,
                                        template_visible: !is_type_only,
                                        callable: false,
                                        type_annotation: None,
                                        span_start: spec.local.span.start as usize,
                                        span_end: spec.local.span.end as usize,
                                    });
                                }
                                ImportDeclarationSpecifier::ImportDefaultSpecifier(spec) => {
                                    let local_name = spec.local.name.as_str().to_string();
                                    response.imports.push(ImportRecord {
                                        source: source_name.clone(),
                                        kind: "default".to_string(),
                                        imported_name: None,
                                        local_name: local_name.clone(),
                                        span_start: decl.span.start as usize,
                                        span_end: decl.span.end as usize,
                                    });
                                    response.bindings.push(BindingRecord {
                                        name: local_name,
                                        kind: if declaration_is_type_only {
                                            "type_only".to_string()
                                        } else {
                                            "import".to_string()
                                        },
                                        exported: false,
                                        template_visible: !declaration_is_type_only,
                                        callable: false,
                                        type_annotation: None,
                                        span_start: spec.local.span.start as usize,
                                        span_end: spec.local.span.end as usize,
                                    });
                                }
                                ImportDeclarationSpecifier::ImportNamespaceSpecifier(spec) => {
                                    let local_name = spec.local.name.as_str().to_string();
                                    response.imports.push(ImportRecord {
                                        source: source_name.clone(),
                                        kind: "namespace".to_string(),
                                        imported_name: Some("*".to_string()),
                                        local_name: local_name.clone(),
                                        span_start: decl.span.start as usize,
                                        span_end: decl.span.end as usize,
                                    });
                                    response.bindings.push(BindingRecord {
                                        name: local_name,
                                        kind: if declaration_is_type_only {
                                            "type_only".to_string()
                                        } else {
                                            "import".to_string()
                                        },
                                        exported: false,
                                        template_visible: !declaration_is_type_only,
                                        callable: false,
                                        type_annotation: None,
                                        span_start: spec.local.span.start as usize,
                                        span_end: spec.local.span.end as usize,
                                    });
                                }
                            }
                        }
                    }
                }
            }
            Statement::ExportNamedDeclaration(decl) => {
                if let Some(declaration) = &decl.declaration {
                    collect_declaration(
                        declaration,
                        true,
                        &source,
                        response.props.as_mut(),
                        &mut response.bindings,
                    );
                }
            }
            _ => {}
        }

        if let Some(declaration) = statement.as_declaration() {
            collect_declaration(
                declaration,
                false,
                &source,
                response.props.as_mut(),
                &mut response.bindings,
            );
        }
    }

    if let Some(props) = response.props.as_ref() {
        if !props.has_props_export {
            response.diagnostics.push(DiagnosticRecord {
                severity: "error".to_string(),
                message: "Missing `export let props: Props` declaration".to_string(),
                span_start: 0,
                span_end: 0,
                line: 0,
                column: 0,
                code: None,
            });
        } else if props.props_type_name.is_none() {
            response.diagnostics.push(DiagnosticRecord {
                severity: "error".to_string(),
                message: "Props export is missing a type annotation".to_string(),
                span_start: 0,
                span_end: 0,
                line: 0,
                column: 0,
                code: None,
            });
        }
    }

    to_json_ptr(&response)
}

#[no_mangle]
pub extern "C" fn weiv_backend_free(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    unsafe {
        drop(CString::from_raw(ptr));
    }
}

#[no_mangle]
pub extern "C" fn weiv_transpile_module(
    source: *const c_char,
    source_path: *const c_char,
) -> *mut c_char {
    let source = match parse_required_cstr(source) {
        Some(value) => value,
        None => return std::ptr::null_mut(),
    };
    let source_path = parse_optional_cstr(source_path).unwrap_or_else(|| "<module>".to_string());

    match transpile_source(&source, &source_path).and_then(|code| CString::new(code).ok()) {
        Some(value) => value.into_raw(),
        None => std::ptr::null_mut(),
    }
}

fn to_json_ptr<T: Serialize>(value: &T) -> *mut c_char {
    match serde_json::to_string(value)
        .ok()
        .and_then(|json| CString::new(json).ok())
    {
        Some(value) => value.into_raw(),
        None => std::ptr::null_mut(),
    }
}

fn parse_required_cstr(value: *const c_char) -> Option<String> {
    if value.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(value).to_str().ok().map(ToOwned::to_owned) }
}

fn parse_optional_cstr(value: *const c_char) -> Option<String> {
    if value.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(value).to_str().ok().map(ToOwned::to_owned) }
}

fn collect_declaration(
    declaration: &Declaration<'_>,
    exported: bool,
    source: &str,
    mut props: Option<&mut PropsRecord>,
    bindings: &mut Vec<BindingRecord>,
) {
    match declaration {
        Declaration::VariableDeclaration(decl) => {
            for declarator in &decl.declarations {
                let kind = match decl.kind {
                    VariableDeclarationKind::Const => "immutable",
                    _ => "mutable",
                };
                let type_annotation = declarator
                    .type_annotation
                    .as_ref()
                    .map(|annotation| annotation.span.source_text(source).trim_start_matches(':').trim().to_string());

                let mut names = Vec::new();
                collect_binding_names(&declarator.id, &mut names);
                for (name, span_start, span_end) in names {
                    if exported && name == "props" {
                        if let Some(props_record) = props.as_deref_mut() {
                            props_record.has_props_export = true;
                            props_record.props_binding_name = Some(name.clone());
                            props_record.props_type_name = type_annotation.clone();
                        }
                    }
                    bindings.push(BindingRecord {
                        name,
                        kind: kind.to_string(),
                        exported,
                        template_visible: true,
                        callable: false,
                        type_annotation: type_annotation.clone(),
                        span_start,
                        span_end,
                    });
                }
            }
        }
        Declaration::FunctionDeclaration(function) => {
            if let Some(id) = &function.id {
                bindings.push(BindingRecord {
                    name: id.name.as_str().to_string(),
                    kind: "function".to_string(),
                    exported,
                    template_visible: true,
                    callable: true,
                    type_annotation: None,
                    span_start: id.span.start as usize,
                    span_end: id.span.end as usize,
                });
            }
        }
        Declaration::TSInterfaceDeclaration(interface) => {
            bindings.push(BindingRecord {
                name: interface.id.name.as_str().to_string(),
                kind: "type_only".to_string(),
                exported,
                template_visible: false,
                callable: false,
                type_annotation: None,
                span_start: interface.id.span.start as usize,
                span_end: interface.id.span.end as usize,
            });
        }
        Declaration::TSTypeAliasDeclaration(alias) => {
            bindings.push(BindingRecord {
                name: alias.id.name.as_str().to_string(),
                kind: "type_only".to_string(),
                exported,
                template_visible: false,
                callable: false,
                type_annotation: None,
                span_start: alias.id.span.start as usize,
                span_end: alias.id.span.end as usize,
            });
        }
        _ => {}
    }
}

fn collect_binding_names(pattern: &BindingPattern<'_>, out: &mut Vec<(String, usize, usize)>) {
    match pattern {
        BindingPattern::BindingIdentifier(id) => {
            out.push((
                id.name.as_str().to_string(),
                id.span.start as usize,
                id.span.end as usize,
            ));
        }
        BindingPattern::AssignmentPattern(assign) => {
            collect_binding_names(&assign.left, out);
        }
        BindingPattern::ObjectPattern(object) => {
            for property in &object.properties {
                collect_binding_names(&property.value, out);
            }
            if let Some(rest) = &object.rest {
                collect_binding_names(&rest.argument, out);
            }
        }
        BindingPattern::ArrayPattern(array) => {
            for element in &array.elements {
                if let Some(element) = element {
                    collect_binding_names(element, out);
                }
            }
            if let Some(rest) = &array.rest {
                collect_binding_names(&rest.argument, out);
            }
        }
    }
}

fn module_export_name(name: &oxc_ast::ast::ModuleExportName<'_>) -> String {
    match name {
        oxc_ast::ast::ModuleExportName::IdentifierName(it) => it.name.as_str().to_string(),
        oxc_ast::ast::ModuleExportName::IdentifierReference(it) => it.name.as_str().to_string(),
        oxc_ast::ast::ModuleExportName::StringLiteral(it) => it.value.as_str().to_string(),
    }
}

fn transpile_source(source: &str, source_path: &str) -> Option<String> {
    let allocator = Allocator::default();
    let source_type = SourceType::from_path(source_path).unwrap_or(SourceType::ts());
    let parsed = Parser::new(&allocator, source, source_type).parse();
    if !parsed.errors.is_empty() {
        return None;
    }

    let mut program = parsed.program;
    let semantic = SemanticBuilder::new().build(&program);
    let scoping = semantic.semantic.into_scoping();
    let options = TransformOptions::default();
    let _ = Transformer::new(&allocator, Path::new(source_path), &options)
        .build_with_scoping(scoping, &mut program);

    let generated = Codegen::new().with_options(CodegenOptions::default()).build(&program);
    Some(generated.code)
}
