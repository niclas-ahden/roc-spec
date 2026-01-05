app [Model, init!, respond!] {
    pf: platform "https://github.com/growthagent/basic-webserver/releases/download/0.15.0/HUvmkDBBkVzixg3f4HuJvb4KfEOpRlY4MS_JRbhbna8.tar.br",
}

import pf.Http exposing [Request, Response]

Model : {}

init! : {} => Result Model []
init! = |{}| Ok({})

respond! : Request, Model => Result Response []_
respond! = |_request, _model|
    Ok({ status: 200, headers: [], body: Str.to_utf8("OK") })
