(* The cache's files: where the copies of Http_cache are kept, between
   runs.

     ~/.cache/mini-chrome/              (XDG_CACHE_HOME; profile=DIR: DIR/Cache)
       3f9a...c1   one file a copy, named by the SHA-256 of its address:
       a07b...2e   the address, when it was kept, the headers, the body
       ...         (Http_cache.to_string)

   A file a copy and no index: what is kept is what the directory
   holds, a copy is found by its name alone, and two threads keeping
   two answers write two files. The name is a hash because an address
   is not a file's name (its slashes, its length); the address is
   written in the file too, and checked when read.

   The whole is held under a size ([limit], 200 MB): when it passes
   it, the copies used longest ago go first, until a tenth is free. A
   copy read has its file's time set to now, so "used longest ago" is
   the file system's own order (ls -lt): the least recently used, the
   rule of every cache since the pages of a virtual memory.

   Read and written where the request is made, on a thread of the pool
   (Fetch): no frame waits for the disk. Each file opened is said (-v),
   as the profile's are, and opened with the capability to.

   profile=off keeps no cache, nor does cache=off; about:cache lists
   what is kept.

   modern:
   Chrome's "simple cache" (Linux, Android, since 2013) is this shape,
   a file an entry named by a hash of its key, chosen over the one
   before it -- a few large files with an index and its own allocator,
   after a file system's -- for being hard to corrupt: a crash loses
   a file, not the cache. Firefox's is a file an entry as well.

   References: RFC 9111 (the rules: Http_cache.mli); The Chromium
   Projects, "Disk Cache" and "Very Simple Backend". *)

(* where the cache is, by the environment: XDG_CACHE_HOME, else
 * ~/.cache, then mini-chrome *)
val default_dir : < Cap.env ; .. > -> string option

(* the cache of that directory (made when first written to) *)
val store : < Cap.open_in ; Cap.open_out ; .. > -> ?limit:int -> dir:string -> unit -> Http_cache.store

(* about:cache: what is kept, the most recently used first *)
val page : now:float -> Http_cache.store option -> string
