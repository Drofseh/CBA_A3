/* ----------------------------------------------------------------------------
@description Logs an error message to the RPT log.
---------------------------------------------------------------------------- */

#include "script_component.hpp"

SCRIPT(error);

// -----------------------------------------------------------------------------
PARAMS_4(_file,_lineNum,_title,_message);

private ["_time", "_lines"];

// TODO: popup window with error message in it.
_time = [time, "H:MM:SS.mmm"] call CBA_fnc_formatElapsedTime;

diag_log text format ["%1 [%2:%3] -ERROR- %4", _time, _file, _lineNum + 1, _title];

_lines = [_message, "\n"] call CBA_fnc_split;

{
	diag_log text format ["            %1", _x];
} forEach _lines;

nil;
