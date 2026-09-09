// OFFICIALLY EXTRACTED lucide icon path data (zcode.z.ai remote v4 bundle,
// 2026-09-07). Rendered via LucideIcon (stroke 2, round caps, 24x24 grid).
// Regenerate with the bundle dig script when the official build changes.
// IGNORE_SIZE lint is fine — no widgets here.
import 'package:flutter/material.dart';

/// One drawable shape from a lucide icon definition.
/// kind: p=path(d) c=circle(cx,cy,r,fill) l=line(x1,y1,x2,y2)
///       r=rect(x,y,w,h,rx) pl=polyline(points)
class LucideShape {
  final String kind;
  final List<String> args;
  const LucideShape(this.kind, this.args);
}

class LucideIconData {
  final String name;
  final List<LucideShape> shapes;
  const LucideIconData(this.name, this.shapes);
}

const Map<String, LucideIconData> kOfficialIcons = {
  "gift": LucideIconData("gift", [
    LucideShape('p', ["M12 7v14"]),
    LucideShape('p', ["M20 11v8a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2v-8"]),
    LucideShape('p', [
      "M7.5 7a1 1 0 0 1 0-5A4.8 8 0 0 1 12 7a4.8 8 0 0 1 4.5-5 1 1 0 0 1 0 5"
    ]),
    LucideShape('r', ["3", "7", "18", "4", "1"]),
  ]),
  "arrow-down": LucideIconData("arrow-down", [
    LucideShape('p', ["M12 5v14"]),
    LucideShape('p', ["m19 12-7 7-7-7"]),
  ]),
  "pin": LucideIconData("pin", [
    LucideShape('p', ["M12 17v5"]),
    LucideShape('p', [
      "M9 10.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24V16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V7a1 1 0 0 1 1-1 2 2 0 0 0 0-4H8a2 2 0 0 0 0 4 1 1 0 0 1 1 1z"
    ]),
  ]),
  "pin-off": LucideIconData("pin-off", [
    LucideShape('p', ["M12 17v5"]),
    LucideShape('p', ["M15 9.34V7a1 1 0 0 1 1-1 2 2 0 0 0 0-4H7.89"]),
    LucideShape('p', ["m2 2 20 20"]),
    LucideShape('p', [
      "M9 9v1.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24V16a1 1 0 0 0 1 1h11"
    ]),
  ]),
  "archive": LucideIconData("archive", [
    LucideShape('r', ["2", "3", "20", "5", "1"]),
    LucideShape('p', ["M4 8v11a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8"]),
    LucideShape('p', ["M10 12h4"]),
  ]),
  "archive-restore": LucideIconData("archive-restore", [
    LucideShape('r', ["2", "3", "20", "5", "1"]),
    LucideShape('p', ["M4 8v11a2 2 0 0 0 2 2h2"]),
    LucideShape('p', ["M20 8v11a2 2 0 0 1-2 2h-2"]),
    LucideShape('p', ["m9 15 3-3 3 3"]),
    LucideShape('p', ["M12 12v9"]),
  ]),
  "trash-2": LucideIconData("trash-2", [
    LucideShape('p', ["M10 11v6"]),
    LucideShape('p', ["M14 11v6"]),
    LucideShape('p', ["M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"]),
    LucideShape('p', ["M3 6h18"]),
    LucideShape('p', ["M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"]),
  ]),
  "refresh-cw": LucideIconData("refresh-cw", [
    LucideShape('p', ["M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8"]),
    LucideShape('p', ["M21 3v5h-5"]),
    LucideShape('p', ["M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16"]),
    LucideShape('p', ["M8 16H3v5"]),
  ]),
  "info": LucideIconData("info", [
    LucideShape('c', ["12", "12", "10", "false"]),
    LucideShape('p', ["M12 16v-4"]),
    LucideShape('p', ["M12 8h.01"]),
  ]),
  "list-filter": LucideIconData("list-filter", [
    LucideShape('p', ["M2 5h20"]),
    LucideShape('p', ["M6 12h12"]),
    LucideShape('p', ["M9 19h6"]),
  ]),
  "chevrons-down-up": LucideIconData("chevrons-down-up", [
    LucideShape('p', ["m7 20 5-5 5 5"]),
    LucideShape('p', ["m7 4 5 5 5-5"]),
  ]),
  "blocks": LucideIconData("blocks", [
    LucideShape('p', [
      "M10 22V7a1 1 0 0 0-1-1H4a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-5a1 1 0 0 0-1-1H2"
    ]),
    LucideShape('r', ["14", "2", "8", "8", "1"]),
  ]),
  "message-circle-plus": LucideIconData("message-circle-plus", [
    LucideShape('p', [
      "M2.992 16.342a2 2 0 0 1 .094 1.167l-1.065 3.29a1 1 0 0 0 1.236 1.168l3.413-.998a2 2 0 0 1 1.099.092 10 10 0 1 0-4.777-4.719"
    ]),
    LucideShape('p', ["M8 12h8"]),
    LucideShape('p', ["M12 8v8"]),
  ]),
  "list": LucideIconData("list", [
    LucideShape('p', ["M3 5h.01"]),
    LucideShape('p', ["M3 12h.01"]),
    LucideShape('p', ["M3 19h.01"]),
    LucideShape('p', ["M8 5h13"]),
    LucideShape('p', ["M8 12h13"]),
    LucideShape('p', ["M8 19h13"]),
  ]),
  "settings": LucideIconData("settings", [
    LucideShape('p', [
      "M9.671 4.136a2.34 2.34 0 0 1 4.659 0 2.34 2.34 0 0 0 3.319 1.915 2.34 2.34 0 0 1 2.33 4.033 2.34 2.34 0 0 0 0 3.831 2.34 2.34 0 0 1-2.33 4.033 2.34 2.34 0 0 0-3.319 1.915 2.34 2.34 0 0 1-4.659 0 2.34 2.34 0 0 0-3.32-1.915 2.34 2.34 0 0 1-2.33-4.033 2.34 2.34 0 0 0 0-3.831A2.34 2.34 0 0 1 6.35 6.051a2.34 2.34 0 0 0 3.319-1.915"
    ]),
    LucideShape('c', ["12", "12", "3", "false"]),
  ]),
  "monitor": LucideIconData("monitor", [
    LucideShape('r', ["2", "3", "20", "14", "2"]),
    LucideShape('l', ["8", "21", "16", "21"]),
    LucideShape('l', ["12", "17", "12", "21"]),
  ]),
  "panel-left": LucideIconData("panel-left", [
    LucideShape('r', ["3", "3", "18", "18", "2"]),
    LucideShape('p', ["M9 3v18"]),
  ]),
  "panel-right": LucideIconData("panel-right", [
    LucideShape('r', ["3", "3", "18", "18", "2"]),
    LucideShape('p', ["M15 3v18"]),
  ]),
  "user": LucideIconData("user", [
    LucideShape('p', ["M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2"]),
    LucideShape('c', ["12", "7", "4", "false"]),
  ]),
  "laptop": LucideIconData("laptop", [
    LucideShape('p', [
      "M18 5a2 2 0 0 1 2 2v8.526a2 2 0 0 0 .212.897l1.068 2.127a1 1 0 0 1-.9 1.45H3.62a1 1 0 0 1-.9-1.45l1.068-2.127A2 2 0 0 0 4 15.526V7a2 2 0 0 1 2-2z"
    ]),
    LucideShape('p', ["M20.054 15.987H3.946"]),
  ]),
  "bell": LucideIconData("bell", [
    LucideShape('p', ["M10.268 21a2 2 0 0 0 3.464 0"]),
    LucideShape('p', [
      "M3.262 15.326A1 1 0 0 0 4 17h16a1 1 0 0 0 .74-1.673C19.41 13.956 18 12.499 18 8A6 6 0 0 0 6 8c0 4.499-1.411 5.956-2.738 7.326"
    ]),
  ]),
  "chevrons-up-down": LucideIconData("chevrons-up-down", [
    LucideShape('p', ["m7 15 5 5 5-5"]),
    LucideShape('p', ["m7 9 5-5 5 5"]),
  ]),
  "arrow-up": LucideIconData("arrow-up", [
    LucideShape('p', ['m5 12 7-7 7 7']),
    LucideShape('p', ['M12 19V5']),
  ]),
  "brain": LucideIconData("brain", [
    LucideShape('p', ['M12 18V5']),
    LucideShape('p', ['M15 13a4.17 4.17 0 0 1-3-4 4.17 4.17 0 0 1-3 4']),
    LucideShape('p', ['M17.598 6.5A3 3 0 1 0 12 5a3 3 0 1 0-5.598 1.5']),
    LucideShape('p', ['M17.997 5.125a4 4 0 0 1 2.526 5.77']),
    LucideShape('p', ['M18 18a4 4 0 0 0 2-7.464']),
    LucideShape('p', ['M19.967 17.483A4 4 0 1 1 12 18a4 4 0 1 1-7.967-.517']),
    LucideShape('p', ['M6 18a4 4 0 0 1-2-7.464']),
    LucideShape('p', ['M6.003 5.125a4 4 0 0 0-2.526 5.77']),
  ]),
  "circle-stop": LucideIconData("circle-stop", [
    LucideShape('c', ['12', '12', '10', 'false']),
    LucideShape('r', ['9', '9', '6', '6', '1']),
  ]),
  "ellipsis": LucideIconData("ellipsis", [
    LucideShape('c', ['12', '12', '1', 'false']),
    LucideShape('c', ['19', '12', '1', 'false']),
    LucideShape('c', ['5', '12', '1', 'false']),
  ]),
  "file-diff": LucideIconData("file-diff", [
    LucideShape('p', [
      'M6 22a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h8a2.4 2.4 0 0 1 1.704.706l3.588 3.588A2.4 2.4 0 0 1 20 8v12a2 2 0 0 1-2 2z'
    ]),
    LucideShape('p', ['M9 10h6']),
    LucideShape('p', ['M12 13V7']),
    LucideShape('p', ['M9 17h6']),
  ]),
  "list-todo": LucideIconData("list-todo", [
    LucideShape('p', ['M13 5h8']),
    LucideShape('p', ['M13 12h8']),
    LucideShape('p', ['M13 19h8']),
    LucideShape('p', ['m3 17 2 2 4-4']),
    LucideShape('r', ['3', '4', '6', '6', '1']),
  ]),
  "package": LucideIconData("package", [
    LucideShape('p', [
      'M11 21.73a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73z'
    ]),
    LucideShape('p', ['M12 22V12']),
    LucideShape('pl', ['3.29 7 12 12 20.71 7']),
    LucideShape('p', ['m7.5 4.27 9 5.15']),
  ]),
  "paperclip": LucideIconData("paperclip", [
    LucideShape('p', [
      'm16 6-8.414 8.586a2 2 0 0 0 2.829 2.829l8.414-8.586a4 4 0 1 0-5.657-5.657l-8.379 8.551a6 6 0 1 0 8.485 8.485l8.379-8.551'
    ]),
  ]),
  "sliders-horizontal": LucideIconData("sliders-horizontal", [
    LucideShape('p', ['M10 5H3']),
    LucideShape('p', ['M12 19H3']),
    LucideShape('p', ['M14 3v4']),
    LucideShape('p', ['M16 17v4']),
    LucideShape('p', ['M21 12h-9']),
    LucideShape('p', ['M21 19h-5']),
    LucideShape('p', ['M21 5h-7']),
    LucideShape('p', ['M8 10v4']),
    LucideShape('p', ['M8 12H3']),
  ]),
  "chevron-down": LucideIconData("chevron-down", [
    LucideShape('p', ['m6 9 6 6 6-6']),
  ]),
  "chevron-up": LucideIconData("chevron-up", [
    LucideShape('p', ['m18 15-6-6-6 6']),
  ]),
  "chevron-right": LucideIconData("chevron-right", [
    LucideShape('p', ['m9 18 6-6-6-6']),
  ]),
  "plus": LucideIconData("plus", [
    LucideShape('p', ['M5 12h14']),
    LucideShape('p', ['M12 5v14']),
  ]),
  "check": LucideIconData("check", [
    LucideShape('p', ['M20 6 9 17l-5-5']),
  ]),
  "x": LucideIconData("x", [
    LucideShape('p', ['M18 6 6 18']),
    LucideShape('p', ['m6 6 12 12']),
  ]),
  "sparkles": LucideIconData("sparkles", [
    LucideShape('p', [
      'M11.017 2.814a1 1 0 0 1 1.966 0l1.051 5.558a2 2 0 0 0 1.594 1.594l5.558 1.051a1 1 0 0 1 0 1.966l-5.558 1.051a2 2 0 0 0-1.594 1.594l-1.051 5.558a1 1 0 0 1-1.966 0l-1.051-5.558a2 2 0 0 0-1.594-1.594l-5.558-1.051a1 1 0 0 1 0-1.966l5.558-1.051a2 2 0 0 0 1.594-1.594z'
    ]),
    LucideShape('p', ['M20 2v4']),
    LucideShape('p', ['M22 4h-4']),
    LucideShape('c', ['4', '20', '2', 'false']),
  ]),
  "copy": LucideIconData("copy", [
    LucideShape('r', ['8', '8', '14', '14', '2']),
    LucideShape(
        'p', ['M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2']),
  ]),
  "thumbs-up": LucideIconData("thumbs-up", [
    LucideShape('p', [
      'M15 5.88 14 10h5.83a2 2 0 0 1 1.92 2.56l-2.33 8A2 2 0 0 1 17.5 22H4a2 2 0 0 1-2-2v-8a2 2 0 0 1 2-2h2.76a2 2 0 0 0 1.79-1.11L12 2a3.13 3.13 0 0 1 3 3.88Z'
    ]),
    LucideShape('p', ['M7 10v12']),
  ]),
  "thumbs-down": LucideIconData("thumbs-down", [
    LucideShape('p', [
      'M9 18.12 10 14H4.17a2 2 0 0 1-1.92-2.56l2.33-8A2 2 0 0 1 6.5 2H20a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-2.76a2 2 0 0 0-1.79 1.11L12 22a3.13 3.13 0 0 1-3-3.88Z'
    ]),
    LucideShape('p', ['M17 14V2']),
  ]),
  "terminal": LucideIconData("terminal", [
    LucideShape('p', ['M12 19h8']),
    LucideShape('p', ['m4 17 6-6-6-6']),
  ]),
  "square-terminal": LucideIconData("square-terminal", [
    LucideShape('p', ['m7 11 2-2-2-2']),
    LucideShape('p', ['M11 13h4']),
    LucideShape('r', ['3', '3', '18', '18', '2']),
  ]),
  "search": LucideIconData("search", [
    LucideShape('p', ['m21 21-4.34-4.34']),
    LucideShape('c', ['11', '11', '8', 'false']),
  ]),
  "earth": LucideIconData("earth", [
    LucideShape('p', ['M21.54 15H17a2 2 0 0 0-2 2v4.54']),
    LucideShape('p', [
      'M7 3.34V5a3 3 0 0 0 3 3a2 2 0 0 1 2 2c0 1.1.9 2 2 2a2 2 0 0 0 2-2c0-1.1.9-2 2-2h3.17'
    ]),
    LucideShape('p',
        ['M11 21.95V18a2 2 0 0 0-2-2a2 2 0 0 1-2-2v-1a2 2 0 0 0-2-2H2.05']),
    LucideShape('c', ['12', '12', '10', 'false']),
  ]),
  "globe": LucideIconData("globe", [
    LucideShape('c', ['12', '12', '10', 'false']),
    LucideShape('p', ['M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20']),
    LucideShape('p', ['M2 12h20']),
  ]),
  "bot": LucideIconData("bot", [
    LucideShape('p', ['M12 8V4H8']),
    LucideShape('r', ['4', '8', '16', '12', '2']),
    LucideShape('p', ['M2 14h2']),
    LucideShape('p', ['M20 14h2']),
    LucideShape('p', ['M15 13v2']),
    LucideShape('p', ['M9 13v2']),
  ]),
  "git-branch": LucideIconData("git-branch", [
    LucideShape('l', ['6', '3', '6', '15']),
    LucideShape('c', ['18', '6', '3', 'false']),
    LucideShape('c', ['6', '18', '3', 'false']),
    LucideShape('p', ['M18 9a9 9 0 0 1-9 9']),
  ]),
  "at-sign": LucideIconData("at-sign", [
    LucideShape('c', ['12', '12', '4', 'false']),
    LucideShape('p', ['M16 8v5a3 3 0 0 0 6 0v-1a10 10 0 1 0-4 8']),
  ]),
  "square-slash": LucideIconData("square-slash", [
    LucideShape('r', ['3', '3', '18', '18', '2']),
    LucideShape('l', ['9', '15', '15', '9']),
  ]),
  "dollar-sign": LucideIconData("dollar-sign", [
    LucideShape('l', ['12', '2', '12', '22']),
    LucideShape('p', ['M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6']),
  ]),
  "hand": LucideIconData("hand", [
    LucideShape('p', ['M18 11V6a2 2 0 0 0-2-2a2 2 0 0 0-2 2']),
    LucideShape('p', ['M14 10V4a2 2 0 0 0-2-2a2 2 0 0 0-2 2v2']),
    LucideShape('p', ['M10 10.5V6a2 2 0 0 0-2-2a2 2 0 0 0-2 2v8']),
    LucideShape('p', [
      'M18 8a2 2 0 1 1 4 0v6a8 8 0 0 1-8 8h-2c-2.8 0-4.5-.86-5.99-2.34l-3.6-3.6a2 2 0 0 1 2.83-2.82L7 15'
    ]),
  ]),
  "notepad-text": LucideIconData("notepad-text", [
    LucideShape('p', ['M8 2v4']),
    LucideShape('p', ['M12 2v4']),
    LucideShape('p', ['M16 2v4']),
    LucideShape('r', ['4', '4', '16', '18', '2']),
    LucideShape('p', ['M8 10h6']),
    LucideShape('p', ['M8 14h8']),
    LucideShape('p', ['M8 18h5']),
  ]),
  "shield-check": LucideIconData("shield-check", [
    LucideShape('p', [
      'M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z'
    ]),
    LucideShape('p', ['m9 12 2 2 4-4']),
  ]),
  "shield-alert": LucideIconData("shield-alert", [
    LucideShape('p', [
      'M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z'
    ]),
    LucideShape('p', ['M12 8v4']),
    LucideShape('p', ['M12 16h.01']),
  ]),
  "arrow-left": LucideIconData("arrow-left", [
    LucideShape('p', ['m12 19-7-7 7-7']),
    LucideShape('p', ['M19 12H5']),
  ]),
  "folder": LucideIconData("folder", [
    LucideShape('p', [
      'M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z'
    ]),
  ]),
  "folder-open": LucideIconData("folder-open", [
    LucideShape('p', [
      'm6 14 1.5-2.9A2 2 0 0 1 9.24 10H20a2 2 0 0 1 1.94 2.5l-1.54 6a2 2 0 0 1-1.95 1.5H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h3.9a2 2 0 0 1 1.69.9l.81 1.2a2 2 0 0 0 1.67.9H18a2 2 0 0 1 2 2v2'
    ]),
  ]),
  "alert-triangle": LucideIconData("alert-triangle", [
    LucideShape('p', [
      'm21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3'
    ]),
    LucideShape('p', ['M12 9v4']),
    LucideShape('p', ['M12 17h.01']),
  ]),
};

/// Renders an official lucide icon: 24x24 grid, stroke 2, round caps/joins,
/// fill none except shapes explicitly marked filled (small accent dots).
class LucideIcon extends StatelessWidget {
  final String name;
  final double size;
  final Color? color;

  const LucideIcon(this.name, {super.key, this.size = 16, this.color});

  @override
  Widget build(BuildContext context) {
    final data = kOfficialIcons[name];
    if (data == null) return SizedBox(width: size, height: size);
    final effectiveColor = color ??
        DefaultTextStyle.of(context).style.color ??
        IconTheme.of(context).color ??
        Colors.white;
    return CustomPaint(
      size: Size.square(size),
      painter: _LucidePainter(data, effectiveColor),
    );
  }
}

class _LucidePainter extends CustomPainter {
  final LucideIconData data;
  final Color color;

  _LucidePainter(this.data, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = color;
    for (final shape in data.shapes) {
      switch (shape.kind) {
        case 'p':
          canvas.drawPath(_parsePath(shape.args[0]), stroke);
        case 'c':
          final filled = shape.args.length > 3 && shape.args[3] == 'true';
          canvas.drawCircle(
              Offset(double.parse(shape.args[0]), double.parse(shape.args[1])),
              double.parse(shape.args[2]),
              filled ? fill : stroke);
        case 'l':
          canvas.drawLine(
              Offset(double.parse(shape.args[0]), double.parse(shape.args[1])),
              Offset(double.parse(shape.args[2]), double.parse(shape.args[3])),
              stroke);
        case 'pl':
          final pts = _parsePoints(shape.args[0]);
          if (pts.length >= 2) canvas.drawPath(_poly(pts), stroke);
        case 'r':
          final x = double.parse(shape.args[0]);
          final y = double.parse(shape.args[1]);
          final rect = Rect.fromLTRB(x, y, x + double.parse(shape.args[2]),
              y + double.parse(shape.args[3]));
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  rect, Radius.circular(double.parse(shape.args[4]))),
              stroke);
      }
    }
  }

  Path _poly(List<Offset> pts) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(_LucidePainter oldDelegate) =>
      oldDelegate.data != data || oldDelegate.color != color;
}

List<Offset> _parsePoints(String s) {
  final v = s
      .split(RegExp(r'[ ,]+'))
      .where((e) => e.isNotEmpty)
      .map(double.parse)
      .toList();
  return [
    for (var i = 0; i + 1 < v.length; i += 2) Offset(v[i], v[i + 1]),
  ];
}

// --- Minimal SVG path parser (M L H V C S Q T A Z, absolute + relative). ---

Path _parsePath(String d) {
  final path = Path();
  var cx = 0.0, cy = 0.0, sx = 0.0, sy = 0.0;
  var lastCx = 0.0, lastCy = 0.0, lastQx = 0.0, lastQy = 0.0;
  var i = 0;
  String? cmd;

  bool sep(int c) => c <= 0x20 || c == 0x2C;

  double num() {
    while (i < d.length && sep(d.codeUnitAt(i))) {
      i++;
    }
    final start = i;
    if (i < d.length && (d[i] == '-' || d[i] == '+')) i++;
    var dotSeen = false;
    var expSeen = false;
    while (i < d.length) {
      final c = d.codeUnitAt(i);
      if (c >= 0x30 && c <= 0x39) {
        i++;
      } else if (c == 0x2E && !dotSeen && !expSeen) {
        // SVG 隐式分隔：第二个小数点开启下一个数字（`1.704.706` =
        // 1.704 与 .706），并入当前 token 会让 double.parse 抛
        // FormatException——earth/file-diff 等字形曾因此在 paint 期
        // 炸掉整行工具卡。
        dotSeen = true;
        i++;
      } else if ((c == 0x65 || c == 0x45) && !expSeen && i > start) {
        expSeen = true;
        i++;
        if (i < d.length && (d[i] == '-' || d[i] == '+')) i++;
      } else {
        break;
      }
    }
    return double.parse(d.substring(start, i));
  }

  bool nextIsNumber() {
    var j = i;
    while (j < d.length && sep(d.codeUnitAt(j))) {
      j++;
    }
    if (j >= d.length) return false;
    final c = d[j];
    return c == '-' ||
        c == '+' ||
        c == '.' ||
        (c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39);
  }

  while (i < d.length) {
    while (i < d.length && sep(d.codeUnitAt(i))) {
      i++;
    }
    if (i >= d.length) break;
    final ch = d[i];
    if ('MmLlHhVvCcSsQqTtAaZz'.contains(ch)) {
      cmd = ch;
      i++;
    } else if (cmd == null) {
      break;
    }
    switch (cmd) {
      case 'M' || 'm':
        if (cmd == 'M') {
          cx = num();
          cy = num();
        } else {
          cx += num();
          cy += num();
        }
        sx = cx;
        sy = cy;
        path.moveTo(cx, cy);
        // 小写 m 之后的隐式线段是相对的（官方 arrow-up/chevron 均以此
        // 起笔，误当绝对坐标会画出飞出画布的"竖线"）。
        cmd = cmd == 'm' ? 'l' : 'L';
      case 'L' || 'l':
        while (nextIsNumber()) {
          if (cmd == 'L') {
            cx = num();
            cy = num();
          } else {
            cx += num();
            cy += num();
          }
          path.lineTo(cx, cy);
        }
      case 'H' || 'h':
        while (nextIsNumber()) {
          cx = cmd == 'H' ? num() : cx + num();
          path.lineTo(cx, cy);
        }
      case 'V' || 'v':
        while (nextIsNumber()) {
          cy = cmd == 'V' ? num() : cy + num();
          path.lineTo(cx, cy);
        }
      case 'C' || 'c':
        while (nextIsNumber()) {
          final x1 = num(),
              y1 = num(),
              x2 = num(),
              y2 = num(),
              x = num(),
              y = num();
          if (cmd == 'C') {
            path.cubicTo(x1, y1, x2, y2, x, y);
            lastCx = x2;
            lastCy = y2;
            cx = x;
            cy = y;
          } else {
            path.cubicTo(cx + x1, cy + y1, cx + x2, cy + y2, cx + x, cy + y);
            lastCx = cx + x2;
            lastCy = cy + y2;
            cx += x;
            cy += y;
          }
        }
      case 'S' || 's':
        while (nextIsNumber()) {
          final x2 = num(), y2 = num(), x = num(), y = num();
          final x1 = 2 * cx - lastCx, y1 = 2 * cy - lastCy;
          if (cmd == 'S') {
            path.cubicTo(x1, y1, x2, y2, x, y);
            lastCx = x2;
            lastCy = y2;
            cx = x;
            cy = y;
          } else {
            path.cubicTo(cx + x1, cy + y1, cx + x2, cy + y2, cx + x, cy + y);
            lastCx = cx + x2;
            lastCy = cy + y2;
            cx += x;
            cy += y;
          }
        }
      case 'Q' || 'q':
        while (nextIsNumber()) {
          final qx = num(), qy = num(), x = num(), y = num();
          if (cmd == 'Q') {
            path.quadraticBezierTo(qx, qy, x, y);
          } else {
            path.quadraticBezierTo(cx + qx, cy + qy, cx + x, cy + y);
          }
          lastQx = cmd == 'Q' ? qx : cx + qx;
          lastQy = cmd == 'Q' ? qy : cy + qy;
          cx = cmd == 'Q' ? x : cx + x;
          cy = cmd == 'Q' ? y : cy + y;
        }
      case 'T' || 't':
        while (nextIsNumber()) {
          final x = num(), y = num();
          final qx = 2 * cx - lastQx, qy = 2 * cy - lastQy;
          if (cmd == 'T') {
            path.quadraticBezierTo(qx, qy, x, y);
            cx = x;
            cy = y;
          } else {
            path.quadraticBezierTo(cx + qx, cy + qy, cx + x, cy + y);
            cx += x;
            cy += y;
          }
          lastQx = qx;
          lastQy = qy;
        }
      case 'A' || 'a':
        while (nextIsNumber()) {
          final rx = num(), ry = num(), rot = num();
          final large = num(), sweep = num(), x = num(), y = num();
          final nx = cmd == 'A' ? x : cx + x;
          final ny = cmd == 'A' ? y : cy + y;
          path.arcToPoint(
            Offset(nx, ny),
            radius: Radius.elliptical(rx, ry),
            rotation: rot,
            largeArc: large != 0,
            clockwise: sweep != 0,
          );
          cx = nx;
          cy = ny;
        }
      case 'Z' || 'z':
        path.close();
        cx = sx;
        cy = sy;
    }
  }
  return path;
}
