-module(ar_config).

-export([parse/1, parse_storage_module/1]).

-include_lib("arweave/include/ar.hrl").
-include_lib("arweave/include/ar_consensus.hrl").
-include_lib("arweave/include/ar_config.hrl").

%%%===================================================================
%%% Public interface.
%%%===================================================================

parse(Config) when is_binary(Config) ->
	case ar_serialize:json_decode(Config) of
		{ok, JsonValue} -> parse_options(JsonValue);
		{error, _} -> {error, bad_json, Config}
	end.

parse_storage_module(IOList) ->
	Bin = iolist_to_binary(IOList),
	case binary:split(Bin, <<",">>, [global]) of
		[PartitionNumberBin, PackingBin] ->
			PartitionNumber = binary_to_integer(PartitionNumberBin),
			true = PartitionNumber >= 0,
			parse_storage_module(PartitionNumber, ?PARTITION_SIZE, PackingBin);
		[RangeNumberBin, RangeSizeBin, PackingBin] ->
			RangeNumber = binary_to_integer(RangeNumberBin),
			true = RangeNumber >= 0,
			RangeSize = binary_to_integer(RangeSizeBin),
			true = RangeSize >= 0,
			parse_storage_module(RangeNumber, RangeSize, PackingBin)
	end.

%%%===================================================================
%%% Private functions.
%%%===================================================================

parse_options({KVPairs}) when is_list(KVPairs) ->
	parse_options(KVPairs, #config{});
parse_options(JsonValue) ->
	{error, root_not_object, JsonValue}.

parse_options([{_, null} | Rest], Config) ->
	parse_options(Rest, Config);

parse_options([{<<"config_file">>, _} | _], _) ->
	{error, config_file_set};

parse_options([{<<"peers">>, Peers} | Rest], Config) when is_list(Peers) ->
	case parse_peers(Peers, []) of
		{ok, ParsedPeers} ->
			parse_options(Rest, Config#config{ peers = ParsedPeers });
		error ->
			{error, bad_peers, Peers}
	end;
parse_options([{<<"peers">>, Peers} | _], _) ->
	{error, {bad_type, peers, array}, Peers};

parse_options([{<<"block_gossip_peers">>, Peers} | Rest], Config) when is_list(Peers) ->
	case parse_peers(Peers, []) of
		{ok, ParsedPeers} ->
			parse_options(Rest, Config#config{ block_gossip_peers = ParsedPeers });
		error ->
			{error, bad_peers, Peers}
	end;
parse_options([{<<"block_gossip_peers">>, Peers} | _], _) ->
	{error, {bad_type, peers, array}, Peers};

parse_options([{<<"start_from_block_index">>, true} | Rest], Config) ->
	parse_options(Rest, Config#config{ start_from_block_index = true });
parse_options([{<<"start_from_block_index">>, false} | Rest], Config) ->
	parse_options(Rest, Config#config{ start_from_block_index = false });
parse_options([{<<"start_from_block_index">>, Opt} | _], _) ->
	{error, {bad_type, start_from_block_index, boolean}, Opt};

parse_options([{<<"mine">>, true} | Rest], Config) ->
	parse_options(Rest, Config#config{ mine = true });
parse_options([{<<"mine">>, false} | Rest], Config) ->
	parse_options(Rest, Config);
parse_options([{<<"mine">>, Opt} | _], _) ->
	{error, {bad_type, mine, boolean}, Opt};

parse_options([{<<"port">>, Port} | Rest], Config) when is_integer(Port) ->
	parse_options(Rest, Config#config{ port = Port });
parse_options([{<<"port">>, Port} | _], _) ->
	{error, {bad_type, port, number}, Port};

parse_options([{<<"data_dir">>, DataDir} | Rest], Config) when is_binary(DataDir) ->
	parse_options(Rest, Config#config{ data_dir = binary_to_list(DataDir) });
parse_options([{<<"data_dir">>, DataDir} | _], _) ->
	{error, {bad_type, data_dir, string}, DataDir};

parse_options([{<<"log_dir">>, Dir} | Rest], Config) when is_binary(Dir) ->
	parse_options(Rest, Config#config{ log_dir = binary_to_list(Dir) });
parse_options([{<<"log_dir">>, Dir} | _], _) ->
	{error, {bad_type, log_dir, string}, Dir};

parse_options([{<<"metrics_dir">>, MetricsDir} | Rest], Config) when is_binary(MetricsDir) ->
	parse_options(Rest, Config#config { metrics_dir = binary_to_list(MetricsDir) });
parse_options([{<<"metrics_dir">>, MetricsDir} | _], _) ->
	{error, {bad_type, metrics_dir, string}, MetricsDir};

parse_options([{<<"storage_modules">>, L} | Rest], Config) when is_list(L) ->
	try
		StorageModules = [parse_storage_module(Bin) || Bin <- L],
		parse_options(Rest, Config#config{ storage_modules = StorageModules })
	catch _:_ ->
		{error, {bad_format, storage_modules, "an array of \"[number],[address]\""}, L}
	end;
parse_options([{<<"storage_modules">>, Bin} | _], _) ->
	{error, {bad_type, storage_modules, array}, Bin};

parse_options([{<<"polling">>, Frequency} | Rest], Config) when is_integer(Frequency) ->
	parse_options(Rest, Config#config{ polling = Frequency });
parse_options([{<<"polling">>, Opt} | _], _) ->
	{error, {bad_type, polling, number}, Opt};

parse_options([{<<"block_pollers">>, N} | Rest], Config) when is_integer(N) ->
	parse_options(Rest, Config#config{ block_pollers = N });
parse_options([{<<"block_pollers">>, Opt} | _], _) ->
	{error, {bad_type, block_pollers, number}, Opt};

parse_options([{<<"no_auto_join">>, true} | Rest], Config) ->
	parse_options(Rest, Config#config{ auto_join = false });
parse_options([{<<"no_auto_join">>, false} | Rest], Config) ->
	parse_options(Rest, Config);
parse_options([{<<"no_auto_join">>, Opt} | _], _) ->
	{error, {bad_type, no_auto_join, boolean}, Opt};

parse_options([{<<"diff">>, Diff} | Rest], Config) when is_integer(Diff) ->
	parse_options(Rest, Config#config{ diff = Diff });
parse_options([{<<"diff">>, Diff} | _], _) ->
	{error, {bad_type, diff, number}, Diff};

parse_options([{<<"mining_addr">>, Addr} | Rest], Config) when is_binary(Addr) ->
	case Config#config.mining_addr of
		not_set ->
			case ar_util:safe_decode(Addr) of
				{ok, D} when byte_size(D) == 32 ->
					parse_options(Rest, Config#config{ mining_addr = D });
				_ -> {error, bad_mining_addr, Addr}
			end;
		_ ->
			{error, at_most_one_mining_addr_is_supported, Addr}
	end;
parse_options([{<<"mining_addr">>, Addr} | _], _) ->
	{error, {bad_type, mining_addr, string}, Addr};

parse_options([{<<"max_miners">>, MaxMiners} | Rest], Config) when is_integer(MaxMiners) ->
	parse_options(Rest, Config#config{ max_miners = MaxMiners });
parse_options([{<<"max_miners">>, MaxMiners} | _], _) ->
	{error, {bad_type, max_miners, number}, MaxMiners};

parse_options([{<<"io_threads">>, IOThreads} | Rest], Config) when is_integer(IOThreads) ->
	parse_options(Rest, Config#config{ io_threads = IOThreads });
parse_options([{<<"io_threads">>, IOThreads} | _], _) ->
	{error, {bad_type, io_threads, number}, IOThreads};

parse_options([{<<"hashing_threads">>, Threads} | Rest], Config) when is_integer(Threads) ->
	parse_options(Rest, Config#config{ hashing_threads = Threads });
parse_options([{<<"hashing_threads">>, Threads} | _], _) ->
	{error, {bad_type, hashing_threads, number}, Threads};

parse_options([{<<"mining_server_chunk_cache_size_limit">>, Limit} | Rest], Config)
		when is_integer(Limit) ->
	parse_options(Rest, Config#config{ mining_server_chunk_cache_size_limit = Limit });
parse_options([{<<"mining_server_chunk_cache_size_limit">>, Limit} | _], _) ->
	{error, {bad_type, mining_server_chunk_cache_size_limit, number}, Limit};

parse_options([{<<"stage_one_hashing_threads">>, HashingThreads} | Rest], Config)
		when is_integer(HashingThreads) ->
	parse_options(Rest, Config#config{ stage_one_hashing_threads = HashingThreads });
parse_options([{<<"stage_one_hashing_threads">>, HashingThreads} | _], _) ->
	{error, {bad_type, stage_one_hashing_threads, number}, HashingThreads};

parse_options([{<<"stage_two_hashing_threads">>, HashingThreads} | Rest], Config)
		when is_integer(HashingThreads) ->
	parse_options(Rest, Config#config{ stage_two_hashing_threads = HashingThreads });
parse_options([{<<"stage_two_hashing_threads">>, HashingThreads} | _], _) ->
	{error, {bad_type, stage_two_hashing_threads, number}, HashingThreads};

parse_options([{<<"max_emitters">>, Value} | Rest], Config) when is_integer(Value) ->
	parse_options(Rest, Config#config{ max_emitters = Value });
parse_options([{<<"max_emitters">>, Value} | _], _) ->
	{error, {bad_type, max_emitters, number}, Value};

parse_options([{<<"tx_validators">>, Value} | Rest], Config)
		when is_integer(Value) ->
	parse_options(Rest, Config#config{ tx_validators = Value });
parse_options([{<<"tx_validators">>, Value} | _], _) ->
	{error, {bad_type, tx_validators, number}, Value};

parse_options([{<<"post_tx_timeout">>, Value} | Rest], Config)
		when is_integer(Value) ->
	parse_options(Rest, Config#config{ post_tx_timeout = Value });
parse_options([{<<"post_tx_timeout">>, Value} | _], _) ->
	{error, {bad_type, post_tx_timeout, number}, Value};

parse_options([{<<"tx_propagation_parallelization">>, Value} | Rest], Config)
		when is_integer(Value) ->
	parse_options(Rest, Config#config{ tx_propagation_parallelization = Value });
parse_options([{<<"tx_propagation_parallelization">>, Value} | _], _) ->
	{error, {bad_type, tx_propagation_parallelization, number}, Value};

parse_options([{<<"max_propagation_peers">>, Value} | Rest], Config)
		when is_integer(Value) ->
	parse_options(Rest, Config#config{ max_propagation_peers = Value });
parse_options([{<<"max_propagation_peers">>, Value} | _], _) ->
	{error, {bad_type, max_propagation_peers, number}, Value};

parse_options([{<<"max_block_propagation_peers">>, Value} | Rest], Config)
		when is_integer(Value) ->
	parse_options(Rest, Config#config{ max_block_propagation_peers = Value });
parse_options([{<<"max_block_propagation_peers">>, Value} | _], _) ->
	{error, {bad_type, max_block_propagation_peers, number}, Value};

parse_options([{<<"sync_jobs">>, Value} | Rest], Config)
		when is_integer(Value) ->
	parse_options(Rest, Config#config{ sync_jobs = Value });
parse_options([{<<"sync_jobs">>, Value} | _], _) ->
	{error, {bad_type, sync_jobs, number}, Value};

parse_options([{<<"header_sync_jobs">>, Value} | Rest], Config)
		when is_integer(Value) ->
	parse_options(Rest, Config#config{ header_sync_jobs = Value });
parse_options([{<<"header_sync_jobs">>, Value} | _], _) ->
	{error, {bad_type, header_sync_jobs, number}, Value};

parse_options([{<<"disk_pool_jobs">>, Value} | Rest], Config)
		when is_integer(Value) ->
	parse_options(Rest, Config#config{ disk_pool_jobs = Value });
parse_options([{<<"disk_pool_jobs">>, Value} | _], _) ->
	{error, {bad_type, disk_pool_jobs, number}, Value};

parse_options([{<<"requests_per_minute_limit">>, L} | Rest], Config) when is_integer(L) ->
	parse_options(Rest, Config#config{ requests_per_minute_limit = L });
parse_options([{<<"requests_per_minute_limit">>, L} | _], _) ->
	{error, {bad_type, requests_per_minute_limit, number}, L};

parse_options([{<<"requests_per_minute_limit_by_ip">>, Object} | Rest], Config)
		when is_tuple(Object) ->
	case parse_requests_per_minute_limit_by_ip(Object) of
		{ok, ParsedMap} ->
			parse_options(Rest, Config#config{ requests_per_minute_limit_by_ip = ParsedMap });
		error ->
			{error, bad_requests_per_minute_limit_by_ip, Object}
	end;
parse_options([{<<"requests_per_minute_limit_by_ip">>, Object} | _], _) ->
	{error, {bad_type, requests_per_minute_limit_by_ip, object}, Object};

parse_options([{<<"transaction_blacklists">>, TransactionBlacklists} | Rest], Config)
		when is_list(TransactionBlacklists) ->
	case safe_map(fun binary_to_list/1, TransactionBlacklists) of
		{ok, TransactionBlacklistStrings} ->
			parse_options(Rest, Config#config{
				transaction_blacklist_files = TransactionBlacklistStrings
			});
		error ->
			{error, bad_transaction_blacklists}
	end;
parse_options([{<<"transaction_blacklists">>, TransactionBlacklists} | _], _) ->
	{error, {bad_type, transaction_blacklists, array}, TransactionBlacklists};

parse_options([{<<"transaction_blacklist_urls">>, TransactionBlacklistURLs} | Rest], Config)
		when is_list(TransactionBlacklistURLs) ->
	case safe_map(fun binary_to_list/1, TransactionBlacklistURLs) of
		{ok, TransactionBlacklistURLStrings} ->
			parse_options(Rest, Config#config{
				transaction_blacklist_urls = TransactionBlacklistURLStrings
			});
		error ->
			{error, bad_transaction_blacklist_urls}
	end;
parse_options([{<<"transaction_blacklist_urls">>, TransactionBlacklistURLs} | _], _) ->
	{error, {bad_type, transaction_blacklist_urls, array}, TransactionBlacklistURLs};

parse_options([{<<"transaction_whitelists">>, TransactionWhitelists} | Rest], Config)
		when is_list(TransactionWhitelists) ->
	case safe_map(fun binary_to_list/1, TransactionWhitelists) of
		{ok, TransactionWhitelistStrings} ->
			parse_options(Rest, Config#config{
				transaction_whitelist_files = TransactionWhitelistStrings
			});
		error ->
			{error, bad_transaction_whitelists}
	end;
parse_options([{<<"transaction_whitelists">>, TransactionWhitelists} | _], _) ->
	{error, {bad_type, transaction_whitelists, array}, TransactionWhitelists};

parse_options([{<<"transaction_whitelist_urls">>, TransactionWhitelistURLs} | Rest], Config)
		when is_list(TransactionWhitelistURLs) ->
	case safe_map(fun binary_to_list/1, TransactionWhitelistURLs) of
		{ok, TransactionWhitelistURLStrings} ->
			parse_options(Rest, Config#config{
				transaction_whitelist_urls = TransactionWhitelistURLStrings
			});
		error ->
			{error, bad_transaction_whitelist_urls}
	end;
parse_options([{<<"transaction_whitelist_urls">>, TransactionWhitelistURLs} | _], _) ->
	{error, {bad_type, transaction_whitelist_urls, array}, TransactionWhitelistURLs};

parse_options([{<<"disk_space">>, DiskSpace} | Rest], Config) when is_integer(DiskSpace) ->
	parse_options(Rest, Config#config{ disk_space = DiskSpace * 1024 * 1024 * 1024 });
parse_options([{<<"disk_space">>, DiskSpace} | _], _) ->
	{error, {bad_type, disk_space, number}, DiskSpace};

parse_options([{<<"disk_space_check_frequency">>, Frequency} | Rest], Config)
		when is_integer(Frequency) ->
	parse_options(Rest, Config#config{ disk_space_check_frequency = Frequency * 1000 });
parse_options([{<<"disk_space_check_frequency">>, Frequency} | _], _) ->
	{error, {bad_type, disk_space_check_frequency, number}, Frequency};

parse_options([{<<"ipfs_pin">>, false} | Rest], Config) ->
	parse_options(Rest, Config);
parse_options([{<<"ipfs_pin">>, true} | Rest], Config) ->
	parse_options(Rest, Config#config{ ipfs_pin = true });

parse_options([{<<"init">>, true} | Rest], Config) ->
	parse_options(Rest, Config#config{ init = true });
parse_options([{<<"init">>, false} | Rest], Config) ->
	parse_options(Rest, Config#config{ init = false });
parse_options([{<<"init">>, Opt} | _], _) ->
	{error, {bad_type, init, boolean}, Opt};

parse_options([{<<"internal_api_secret">>, Secret} | Rest], Config)
		when is_binary(Secret), byte_size(Secret) >= ?INTERNAL_API_SECRET_MIN_LEN ->
	parse_options(Rest, Config#config{ internal_api_secret = Secret });
parse_options([{<<"internal_api_secret">>, Secret} | _], _) ->
	{error, bad_secret, Secret};

parse_options([{<<"enable">>, Features} | Rest], Config) when is_list(Features) ->
	case safe_map(fun(Feature) -> binary_to_atom(Feature, latin1) end, Features) of
		{ok, FeatureAtoms} ->
			parse_options(Rest, Config#config{ enable = FeatureAtoms });
		error ->
			{error, bad_enable}
	end;
parse_options([{<<"enable">>, Features} | _], _) ->
	{error, {bad_type, enable, array}, Features};

parse_options([{<<"disable">>, Features} | Rest], Config) when is_list(Features) ->
	case safe_map(fun(Feature) -> binary_to_atom(Feature, latin1) end, Features) of
		{ok, FeatureAtoms} ->
			parse_options(Rest, Config#config{ disable = FeatureAtoms });
		error ->
			{error, bad_disable}
	end;
parse_options([{<<"disable">>, Features} | _], _) ->
	{error, {bad_type, disable, array}, Features};

parse_options([{<<"gateway">>, Domain} | Rest], Config) when is_binary(Domain) ->
	parse_options(Rest, Config#config{ gateway_domain = Domain });
parse_options([{<<"gateway">>, false} | Rest], Config) ->
	parse_options(Rest, Config);
parse_options([{<<"gateway">>, Gateway} | _], _) ->
	{error, {bad_type, gateway, string}, Gateway};

parse_options([{<<"custom_domains">>, CustomDomains} | Rest], Config)
		when is_list(CustomDomains) ->
	case lists:all(fun is_binary/1, CustomDomains) of
		true ->
			parse_options(Rest, Config#config{ gateway_custom_domains = CustomDomains });
		false ->
			{error, bad_custom_domains}
	end;
parse_options([{<<"custom_domains">>, CustomDomains} | _], _) ->
	{error, {bad_type, custom_domains, array}, CustomDomains};

parse_options([{<<"webhooks">>, WebhookConfigs} | Rest], Config) when is_list(WebhookConfigs) ->
	case parse_webhooks(WebhookConfigs, []) of
		{ok, ParsedWebhooks} ->
			parse_options(Rest, Config#config{ webhooks = ParsedWebhooks });
		error ->
			{error, bad_webhooks, WebhookConfigs}
	end;
parse_options([{<<"webhooks">>, Webhooks} | _], _) ->
	{error, {bad_type, webhooks, array}, Webhooks};

parse_options([{<<"semaphores">>, Semaphores} | Rest], Config) when is_tuple(Semaphores) ->
	case parse_atom_number_map(Semaphores, Config#config.semaphores) of
		{ok, ParsedSemaphores} ->
			parse_options(Rest, Config#config{ semaphores = ParsedSemaphores });
		error ->
			{error, bad_semaphores, Semaphores}
	end;
parse_options([{<<"semaphores">>, Semaphores} | _], _) ->
	{error, {bad_type, semaphores, object}, Semaphores};

parse_options([{<<"max_connections">>, MaxConnections} | Rest], Config)
		when is_integer(MaxConnections) ->
	parse_options(Rest, Config#config{ max_connections = MaxConnections });

parse_options([{<<"max_gateway_connections">>, MaxGatewayConnections} | Rest], Config)
		when is_integer(MaxGatewayConnections) ->
	parse_options(Rest, Config#config{ max_gateway_connections = MaxGatewayConnections });

parse_options([{<<"max_poa_option_depth">>, MaxPOAOptionDepth} | Rest], Config)
		when is_integer(MaxPOAOptionDepth) ->
	parse_options(Rest, Config#config{ max_poa_option_depth = MaxPOAOptionDepth });

parse_options([{<<"disk_pool_data_root_expiration_time">>, D} | Rest], Config)
		when is_integer(D) ->
	parse_options(Rest, Config#config{ disk_pool_data_root_expiration_time = D });

parse_options([{<<"max_disk_pool_buffer_mb">>, D} | Rest], Config) when is_integer(D) ->
	parse_options(Rest, Config#config{ max_disk_pool_buffer_mb= D });

parse_options([{<<"max_disk_pool_data_root_buffer_mb">>, D} | Rest], Config)
		when is_integer(D) ->
	parse_options(Rest, Config#config{ max_disk_pool_data_root_buffer_mb = D });

parse_options([{<<"randomx_bulk_hashing_iterations">>, D} | Rest], Config) when is_integer(D) ->
	parse_options(Rest, Config#config{ randomx_bulk_hashing_iterations = D });

parse_options([{<<"disk_cache_size_mb">>, D} | Rest], Config) when is_integer(D) ->
	parse_options(Rest, Config#config{ disk_cache_size = D });

parse_options([{<<"packing_rate">>, D} | Rest], Config) when is_integer(D) ->
	parse_options(Rest, Config#config{ packing_rate = D });

parse_options([{<<"max_nonce_limiter_validation_thread_count">>, D} | Rest], Config)
		when is_integer(D) ->
	parse_options(Rest, Config#config{ max_nonce_limiter_validation_thread_count = D });

parse_options([{<<"max_nonce_limiter_last_step_validation_thread_count">>, D} | Rest], Config)
		when is_integer(D) ->
	parse_options(Rest,
			Config#config{ max_nonce_limiter_last_step_validation_thread_count = D });

parse_options([{<<"vdf_server_trusted_peer">>, <<>>} | Rest], Config) ->
	parse_options(Rest, Config);
parse_options([{<<"vdf_server_trusted_peer">>, Peer} | Rest], Config) ->
	#config{ nonce_limiter_server_trusted_peers = Peers } = Config,
	case ar_util:safe_parse_peer(Peer) of
		{ok, ParsedPeer} ->
			Peers2 = [ParsedPeer | Peers],
			parse_options(Rest, Config#config{ nonce_limiter_server_trusted_peers = Peers2 });
		{error, _} ->
			{error, bad_vdf_server_trusted_peer, Peer}
	end;

parse_options([{<<"vdf_server_trusted_peers">>, Peers} | Rest], Config) when is_list(Peers) ->
	#config{ nonce_limiter_server_trusted_peers = CurrentPeers } = Config,
	case parse_peers(Peers, []) of
		{ok, ParsedPeers} ->
			Peers2 = CurrentPeers ++ ParsedPeers,
			parse_options(Rest, Config#config{ nonce_limiter_server_trusted_peers = Peers2 });
		error ->
			{error, bad_vdf_server_trusted_peers, Peers}
	end;
parse_options([{<<"vdf_server_trusted_peers">>, Peers} | _], _) ->
	{error, {bad_type, vdf_server_trusted_peers, array}, Peers};

parse_options([{<<"vdf_client_peers">>, Peers} | Rest], Config) when is_list(Peers) ->
	case parse_peers(Peers, []) of
		{ok, ParsedPeers} ->
			parse_options(Rest, Config#config{ nonce_limiter_client_peers = ParsedPeers });
		error ->
			{error, bad_vdf_client_peers, Peers}
	end;
parse_options([{<<"vdf_client_peers">>, Peers} | _], _) ->
	{error, {bad_type, vdf_client_peers, array}, Peers};

parse_options([{<<"debug">>, B} | Rest], Config) when is_boolean(B) ->
	parse_options(Rest, Config#config{ debug = B });

parse_options([{<<"run_defragmentation">>, B} | Rest], Config) when is_boolean(B) ->
	parse_options(Rest, Config#config{ run_defragmentation = B });

parse_options([{<<"defragmentation_trigger_threshold">>, D} | Rest], Config)
		when is_integer(D) ->
	parse_options(Rest, Config#config{ defragmentation_trigger_threshold = D });

parse_options([{<<"block_throttle_by_ip_interval">>, D} | Rest], Config)
		when is_integer(D) ->
	parse_options(Rest, Config#config{ block_throttle_by_ip_interval = D });

parse_options([{<<"block_throttle_by_solution_interval">>, D} | Rest], Config)
		when is_integer(D) ->
	parse_options(Rest, Config#config{ block_throttle_by_solution_interval = D });

parse_options([{<<"defragment_modules">>, L} | Rest], Config) when is_list(L) ->
	try
		DefragModules = [parse_storage_module(Bin) || Bin <- L],
		parse_options(Rest, Config#config{ defragmentation_modules = DefragModules })
	catch _:_ ->
		{error, {bad_format, defragment_modules, "an array of \"[number],[address]\""}, L}
	end;
parse_options([{<<"defragment_modules">>, Bin} | _], _) ->
	{error, {bad_type, defragment_modules, array}, Bin};

parse_options([Opt | _], _) ->
	{error, unknown, Opt};
parse_options([], Config) ->
	{ok, Config}.

parse_storage_module(RangeNumber, RangeSize, PackingBin) ->
	Packing =
		case PackingBin of
			<<"unpacked">> ->
				unpacked;
			MiningAddr when byte_size(MiningAddr) == 43 ->
				{spora_2_6, ar_util:decode(MiningAddr)}
		end,
	{RangeSize, RangeNumber, Packing}.

safe_map(Fun, List) ->
	try
		{ok, lists:map(Fun, List)}
	catch
		_:_ -> error
	end.

parse_peers([Peer | Rest], ParsedPeers) ->
	case ar_util:safe_parse_peer(Peer) of
		{ok, ParsedPeer} -> parse_peers(Rest, [ParsedPeer | ParsedPeers]);
		{error, _} -> error
	end;
parse_peers([], ParsedPeers) ->
	{ok, lists:reverse(ParsedPeers)}.

parse_webhooks([{WebhookConfig} | Rest], ParsedWebhookConfigs) when is_list(WebhookConfig) ->
	case parse_webhook(WebhookConfig, #config_webhook{}) of
		{ok, ParsedWebhook} -> parse_webhooks(Rest, [ParsedWebhook | ParsedWebhookConfigs]);
		error -> error
	end;
parse_webhooks([_ | _], _) ->
	error;
parse_webhooks([], ParsedWebhookConfigs) ->
	{ok, lists:reverse(ParsedWebhookConfigs)}.

parse_webhook([{<<"events">>, Events} | Rest], Webhook) when is_list(Events) ->
	case parse_webhook_events(Events, []) of
		{ok, ParsedEvents} ->
			parse_webhook(Rest, Webhook#config_webhook{ events = ParsedEvents });
		error ->
			error
	end;
parse_webhook([{<<"events">>, _} | _], _) ->
	error;
parse_webhook([{<<"url">>, Url} | Rest], Webhook) when is_binary(Url) ->
	parse_webhook(Rest, Webhook#config_webhook{ url = Url });
parse_webhook([{<<"url">>, _} | _], _) ->
	error;
parse_webhook([{<<"headers">>, {Headers}} | Rest], Webhook) when is_list(Headers) ->
	parse_webhook(Rest, Webhook#config_webhook{ headers = Headers });
parse_webhook([{<<"headers">>, _} | _], _) ->
	error;
parse_webhook([], Webhook) ->
	{ok, Webhook}.

parse_webhook_events([Event | Rest], Events) ->
	case Event of
		<<"transaction">> -> parse_webhook_events(Rest, [transaction | Events]);
		<<"block">> -> parse_webhook_events(Rest, [block | Events]);
		_ -> error
	end;
parse_webhook_events([], Events) ->
	{ok, lists:reverse(Events)}.

parse_atom_number_map({[Pair | Pairs]}, Parsed) when is_tuple(Pair) ->
	parse_atom_number_map({Pairs}, parse_atom_number(Pair, Parsed));
parse_atom_number_map({[]}, Parsed) ->
	{ok, Parsed};
parse_atom_number_map(_, _) ->
	error.

parse_atom_number({Name, Number}, Parsed) when is_binary(Name), is_number(Number) ->
	maps:put(binary_to_atom(Name), Number, Parsed);
parse_atom_number({Key, Value}, Parsed) ->
	?LOG_WARNING([{event, parse_config_bad_type},
		{key, io_lib:format("~p", [Key])}, {value, iolib:format("~p", [Value])}]),
	Parsed.

parse_requests_per_minute_limit_by_ip(Input) ->
	parse_requests_per_minute_limit_by_ip(Input, #{}).

parse_requests_per_minute_limit_by_ip({[{IP, Object} | Pairs]}, Parsed) ->
	case ar_util:safe_parse_peer(IP) of
		{error, invalid} ->
			error;
		{ok, {A, B, C, D, _Port}} ->
			case parse_atom_number_map(Object, #{}) of
				error ->
					error;
				{ok, ParsedMap} ->
					parse_requests_per_minute_limit_by_ip({Pairs},
							maps:put({A, B, C, D}, ParsedMap, Parsed))
			end
	end;
parse_requests_per_minute_limit_by_ip({[]}, Parsed) ->
	{ok, Parsed};
parse_requests_per_minute_limit_by_ip(_, _) ->
	error.
