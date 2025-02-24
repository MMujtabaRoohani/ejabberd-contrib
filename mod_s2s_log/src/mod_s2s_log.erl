%%%----------------------------------------------------------------------
%%% File    : mod_s2s_log.erl
%%% Author  : Mickael Remond <mremond@process-one.net>
%%% Purpose : Log all s2s connections in a file
%%% Created :  14 Mar 2008 by Mickael Remond <mremond@process-one.net>
%%%
%%%
%%% ejabberd, Copyright (C) 2002-2020   ProcessOne
%%%
%%% This program is free software; you can redistribute it and/or
%%% modify it under the terms of the GNU General Public License as
%%% published by the Free Software Foundation; either version 2 of the
%%% License, or (at your option) any later version.
%%%
%%% This program is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
%%% General Public License for more details.
%%%
%%% You should have received a copy of the GNU General Public License along
%%% with this program; if not, write to the Free Software Foundation, Inc.,
%%% 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
%%%
%%%----------------------------------------------------------------------
-module(mod_s2s_log).
-author('mremond@process-one.net').

-behaviour(gen_mod).

%% API:
-export([start/2,
         init/1,
	 stop/1,
	 depends/2,
	 mod_doc/0,
	 mod_opt_type/1,
	 mod_status/0,
	 mod_options/1]).
%% Hooks:
-export([reopen_log/0,
	 s2s_out_auth/2,
	 s2s_in_auth/3]).

-include("logger.hrl").

-define(PROCNAME, ?MODULE).
-define(FILE_OPTS, [append,raw]).

-record(config, {filename, iodevice}).

%% For now we only support one log file for all vhosts.
start(Host, Opts) ->
    case whereis(?PROCNAME) of
	undefined ->
	    FilenameStr  = case gen_mod:get_opt(filename, Opts) of
                 auto ->
                    filename:join(filename:dirname(ejabberd_logger:get_log_path()),
                                     "s2s.log");
                           FN -> FN
             end,
            Filename = list_to_binary(FilenameStr),
		    register(?PROCNAME,
			     spawn(?MODULE, init, [#config{filename=Filename}])),
		    ejabberd_hooks:add(reopen_log_hook, ?MODULE, reopen_log, 55),
		    s2s_hooks(Host, add);
	_ ->
	    s2s_hooks(Host, add)
    end.

init(Config)->
    {ok, IOD} = file:open(Config#config.filename, ?FILE_OPTS),
    loop(Config#config{iodevice=IOD}).

loop(Config) ->
    receive
	{s2s_connect, MyServer, Server} ->
	    log_s2s_connection(Config#config.iodevice, MyServer, Server),
	    loop(Config);
	{reopen_log} ->
	    file:close(Config#config.iodevice),
	    {ok, IOD} = file:open(Config#config.filename, ?FILE_OPTS),
	    loop(Config#config{iodevice = IOD});
	{get_filename, Pid} ->
	    Pid ! {filename, Config#config.filename},
	    loop(Config);
	stop ->
	    file:close(Config#config.iodevice),
	    exit(normal)
    end.

stop(Host) ->
    s2s_hooks(Host, delete),
    case gen_mod:is_loaded_elsewhere(Host, ?MODULE) of
	true ->
	    ok;
	false ->
	    ejabberd_hooks:delete(reopen_log_hook, ?MODULE, reopen_log, 55),
	    ?PROCNAME ! stop
    end.

s2s_out_auth(#{remote_server := RServer, server := LServer} = Acc, true) ->
    ?PROCNAME ! {s2s_connect, LServer, RServer},
    Acc;
s2s_out_auth(Acc, _) ->
    Acc.

s2s_in_auth(#{lserver := LServer} = Acc, true, RServer) ->
    ?PROCNAME ! {s2s_connect, RServer, LServer},
    Acc;
s2s_in_auth(Acc, _, _) ->
    Acc.

reopen_log() ->
    ?PROCNAME ! {reopen_log}.

depends(_, _) ->
    [].

mod_opt_type(filename) ->
    econf:either(auto, econf:file(write)).

mod_options(_Host) ->
    [{filename, auto}].

mod_doc() -> #{}.

mod_status() ->
    ?PROCNAME ! {get_filename, self()},
    Filename = receive {filename, F} -> F end,
    io_lib:format("Logging to: ~s", [binary_to_list(Filename)]).

%% ---
%% Internal functions

log_s2s_connection(IODevice, MyServer, Server) ->
    {{Y, M, D}, {H, Min, S}} = calendar:local_time(),
    Date = io_lib:format(template(date), [Y, M, D, H, Min, S]),
    Record = [Date, "|", MyServer, "|", Server, "\n"],
    ok = file:write(IODevice, Record).

template(date) ->
    "~p-~2.2.0w-~2.2.0w ~2.2.0w:~2.2.0w:~2.2.0w".

-spec s2s_hooks(binary(), add | delete) -> ok.
s2s_hooks(Host, add) ->
    ejabberd_hooks:add(s2s_out_auth_result, Host, ?MODULE, s2s_out_auth, 55),
    ejabberd_hooks:add(s2s_in_auth_result, Host, ?MODULE, s2s_in_auth, 55);
s2s_hooks(Host, delete) ->
    ejabberd_hooks:delete(s2s_out_auth_result, Host, ?MODULE, s2s_out_auth, 55),
    ejabberd_hooks:delete(s2s_in_auth_result, Host, ?MODULE, s2s_in_auth, 55).
