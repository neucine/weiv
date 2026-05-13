import * as vscode from "vscode";
import { WeivDefinitionProvider } from "./definition";

export function activate(context: vscode.ExtensionContext) {
  const selector: vscode.DocumentSelector = { language: "weiv", scheme: "file" };

  context.subscriptions.push(
    vscode.languages.registerDefinitionProvider(selector, new WeivDefinitionProvider())
  );
}

export function deactivate() {}
