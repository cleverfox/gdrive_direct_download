%#!/usr/local/bin/escript
-module(download).
-export([main/1,decodefilename/1]).

main(["multi",Name]) ->
  {ok,TxtUrls}=file:read_file("urls/"++Name),
  URLS=[binary_to_list(U) || U<-binary:split(TxtUrls,<<"\n">>,[global])],
  Prefix="files/"++Name++"/",
  case file:read_file_info(Prefix) of
    {ok,_} -> ok;
    {error,enoent} ->
      file:make_dir(Prefix)
  end,

  lists:foreach(fun(URL) ->
                    main([URL,Prefix])
                end, URLS);

main([""|_]) ->
  ok;
main([Arg1|Rest]) ->
  Arg=decode_arg(Arg1),
  application:start(inets),
  application:ensure_all_started(ssl),
  io:format("URL ~s~n",[Arg]),
  %httpc:set_options([{verbose, debug}]),
  {ok,CookiesBin}=file:read_file("cookie.txt"),
  Cookie=[ binary_to_list(C) || C<-binary:split(CookiesBin,<<"\n">>) ],
  case download_link(Arg,undefined,Cookie) of
    false ->
      io:format("File ~s not found",[Arg]);
    RdrTo ->
      io:format("Found link ~s~n",[RdrTo]),
      Headers=[
               {"User-Agent", "Mozilla/5.0 (Windows NT 10.0; rv:68.0) Gecko/20100101 Firefox/68.0"},
               {"Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"},
               {"Accept-Language", "en-US,en;q=0.5"}
              ],
      {ok,{Status2,Hdr2,Body2}}=httpc:request(get,
                                              {RdrTo, Headers},
                                              [
                                               {autoredirect, false}
                                              ], [{body_format, binary}]),
      CD=proplists:get_value("content-disposition", Hdr2),
      Filename=case Rest of 
                 [] ->
                   decodefilename(CD);
                 [Prefix] ->
                   [Prefix, decodefilename(CD)]
               end,

      io:format("Res ~p~n",[Status2]),
      io:format("Res ~p~n",[Filename]),
      file:write_file(Filename,Body2),
      io:format("Res ~p~n",[size(Body2)]),
      ok
  end.

download_link(Arg, Confirm, Cookie) ->
  URL="https://drive.google.com/uc?export=download&id="++Arg++
  if Confirm==undefined -> [];
     true -> "&confirm="++Confirm
  end,
  io:format("Getting ~s~n",[URL]),
  case httpc:request(get,{URL,
                          [
                           {"User-Agent", "Mozilla/5.0 (Windows NT 10.0; rv:68.0) Gecko/20100101 Firefox/68.0"},
                           {"Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"},
                           {"Accept-Language", "en-US,en;q=0.5"}
                          ]++[{"Cookie",C} || C<-Cookie] },[
                              {autoredirect, false}
                             ], [{body_format, binary}]) of 
    {ok,{{"HTTP/1.1",404,_},_,_}} ->
      false;
    {ok,{{"HTTP/1.1",302,"Moved Temporarily"},Hdr,_}} ->
      proplists:get_value("location",Hdr);
    {ok,{{"HTTP/1.1",200,"OK"},Hdr,Body}} when Confirm == undefined ->
      case re:run(Body,"confirm=([\\d\\w\-]+)") of
              {match, [_,{Off,Len}]} ->
                <<_:Off/binary,Payload:Len/binary,_/binary>> = Body,
                SetC=lists:filtermap(fun({"set-cookie",C1}) ->
                                         {true, C1};
                                        (_) -> false
                                     end, Hdr),
                io:format("Add Cookie ~p~n",[SetC]),
                download_link(Arg, binary_to_list(Payload),[SetC|Cookie]);
              Any ->
                     file:write_file("Error",io_lib:format("~p.~n~p.~n~p.~n",[Hdr,Body,Any])),
                     throw('error')
            end
  end.

decodefilename("attachment;"++CD) ->
  case re:run(CD,"filename.=UTF-8..(.+)$") of
    {match, [_,{O,L}]} ->
      unicode:characters_to_list(list_to_binary(http_uri:decode(string:sub_string(CD,O+1,L+O))));
    nomatch ->
      [F1|_]=string:split(CD,";"),
      ["filename"|QFN]=string:split(F1,"="),
      [_,FN,_]=string:split(QFN,"\"",all),
      FN
  end.


%list_to_binary(http_uri:decode("100%20%D1%81%D0%BB%D0%BE%D0%B2%20%D0%B7%D0%B0%20%D1%87%D0%B0%D1%81%20HW5"))

decode_arg(Arg1) ->
  case re:run(Arg1,"id=([\\d\\w\-\_]+)") of
    {match,[_,{O,L}]} ->
      string:sub_string(Arg1,O+1,L+O);
    nomatch ->
      case re:run(Arg1,"/file/d/([\\d\\w\-\_]+)/") of
        {match,[_,{O,L}]} ->
          string:sub_string(Arg1,O+1,L+O);
        nomatch -> throw(Arg1)
      end
  end.

