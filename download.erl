#!/usr/local/bin/escript
main([Arg1|_]) ->
  Arg=decode_arg(Arg1),
  io:format("F ~p~n",[Arg]),
  application:start(inets),
  application:ensure_all_started(ssl),
  io:format("ok ~s~n",[Arg]),
  %httpc:set_options([{verbose, debug}]),
  {ok,CookiesBin}=file:read_file("cookie.txt"),
  Cookie=[ binary_to_list(C) || C<-binary:split(CookiesBin,<<"\n">>) ],
  RdrTo=download_link(Arg,undefined,Cookie),

  io:format("Found link ~s~n",[RdrTo]),

  {ok,{Status2,Hdr2,Body2}}=httpc:request(get,{RdrTo,
                       [
                        {"User-Agent", "Mozilla/5.0 (Windows NT 10.0; rv:68.0) Gecko/20100101 Firefox/68.0"},
                        {"Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"},
                        {"Accept-Language", "en-US,en;q=0.5"}
                       ]},[
                           {autoredirect, false}
                          ], [{body_format, binary}]),

  CD=proplists:get_value("content-disposition", Hdr2),
  Filename=decodefilename(CD),
        
  io:format("Res ~p~n",[Status2]),
  io:format("Res ~p~n",[Filename]),
  file:write_file(Filename,Body2),
  io:format("Res ~p~n",[size(Body2)]),
  ok.

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
    {ok,{{"HTTP/1.1",302,"Moved Temporarily"},Hdr,_}} ->
      proplists:get_value("location",Hdr);
    {ok,{{"HTTP/1.1",200,"OK"},Hdr,Body}} when Confirm == undefined ->
      case re:run(Body,"confirm=([\\d\\w]+)") of
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
  [F1|_]=string:split(CD,";"),
  ["filename"|QFN]=string:split(F1,"="),
  [_,FN,_]=string:split(QFN,"\"",all),
  FN.

decode_arg(Arg1) ->
  {match,[_,{O,L}]}=re:run(Arg1,"id=([\\d\\w\-\_]+)"),
  string:sub_string(Arg1,O+1,L+O).

