module TestCore
using Test
using Accessors
using Accessors: test_getset_laws, test_modify_law
using Accessors: compose, get_update_op
using ConstructionBase: ConstructionBase
using StaticNumbers: StaticNumbers, static

struct T
    a
    b
end

struct TT{A,B}
    a::A
    b::B
end

@testset "get_update_op" begin
    @test get_update_op(:(&=)) === :(&)
    @test get_update_op(:(^=)) === :(^)
    @test get_update_op(:(-=)) === :(-)
    @test get_update_op(:(%=)) === :(%)
    @test_throws ArgumentError get_update_op(:(++))
    @test_throws ArgumentError get_update_op(:(<=))
end

@testset "@reset" begin
    a = 1
    @set a = 2
    @test a === 1
    @reset a = 2
    @test a === 2

    t = T(1, T(2,3))
    @set t.b.a = 20
    @test t === T(1, T(2,3))

    @reset t.b.a = 20
    @test t === T(1,T(20,3))

    a = 1
    @reset a += 10
    @test a === 11
    nt = (a=1,)
    @reset nt.a = 5
    @test nt === (a=5,)
end

@testset "@set" begin

    t = T(1, T(2, T(T(4,4),3)))
    s = @set t.b.b.a.a = 5
    @test t === T(1, T(2, T(T(4,4),3)))
    @test s === T(1, T(2, T(T(5, 4), 3)))
    @test_throws ArgumentError @set t.b.b.a.a.a = 3

    t = T(1,2)
    @test T(1, T(1,2)) === @set t.b = T(1,2)
    @test_throws ArgumentError @set t.c = 3

    t = T(T(2,2), 1)
    s = @set t.a.a = 3
    @test s === T(T(3, 2), 1)

    t = T(1, T(2, T(T(4,4),3)))
    s = @set t.b.b = 4
    @test s === T(1, T(2, 4))

    t = T(1,2)
    s = @set t.a += 1
    @test s === T(2,2)

    t = T(1,2)
    s = @set t.b -= 2
    @test s === T(1,0)

    t = T(10, 20)
    s = @set t.a *= 10
    @test s === T(100, 20)

    t = T(2,1)
    s = @set t.a /= 2
    @test s === T(1.0,1)

    t = T(1, 2)
    s = @set t.a <<= 2
    @test s === T(4, 2)

    t = T(8, 2)
    s = @set t.a >>= 2
    @test s === T(2, 2)

    t = T(1, 2)
    s = @set t.a &= 0
    @test s === T(0, 2)

    t = T(1, 2)
    s = @set t.a |= 2
    @test s === T(3, 2)

    t = T((1,2),(3,4))
    @set t.a[1] = 10
    s1 = @set t.a[1] = 10
    @test s1 === T((10,2),(3,4))
    i = 1
    si = @set t.a[i] = 10
    @test s1 === si
    se = @set t.a[end] = 20
    @test se === T((1,20),(3,4))
    se1 = @set t.a[end-1] = 10
    @test s1 === se1

    s1 = @set t.a[static(1)] = 10
    @test s1 === T((10,2),(3,4))
    i = 1
    si = @set t.a[static(i)] = 10
    @test s1 === si

    t = @set T(1,2).a = 2
    @test t === T(2,2)

    t = (1, 2, 3, 4)
    @test (@set t[length(t)] = 40) === (1, 2, 3, 40)
    @test (@set t[length(t) ÷ 2] = 20) === (1, 20, 3, 4)

    t = (1, 2)
    @test (@set t |> first = 10) === (10, 2)

    @test @set(only((1,)) = 2 ) === (2,)
    @test_throws ArgumentError @set(only((1,2)) = 2 )
end


struct UserDefinedLens end

struct LensIfTextPlain end
Base.show(io::IO, ::MIME"text/plain", ::LensIfTextPlain) =
    print(io, "I define text/plain.")



@testset "lens laws" begin
    obj = T(2, T(T(3,(4,4)), 2))
    i = 2
    for lens ∈ [
            @optic _.a
            @optic _.b
            @optic _.b.a
            @optic _.b.a.b[2]
            @optic _.b.a.b[i]
            @optic _.b.a.b[static(2)]
            @optic _.b.a.b[static(i)]
            @optic _.b.a.b[end]
            @optic _.b.a.b[identity(end) - 1]
            @optic _
        ]
        val1, val2 = randn(2)
        f(x) = (x,x)
        test_getset_laws(lens, obj, val1, val2)
        test_modify_law(f, lens, obj)
    end
end

@testset "type stability" begin
    o1 = 2
    o22 = 2
    o212 = (4,4)
    o211 = 3
    o21 = TT(o211, o212)
    o2 = TT(o21, o22)
    obj = TT(o1, o2)
    @assert obj === TT(2, TT(TT(3,(4,4)), 2))
    i = 1
    @testset "$lens" for (lens, val) ∈ [
          ((@optic _.a           ),   o1 ),
          ((@optic _.b           ),   o2 ),
          ((@optic _.b.a         ),   o21),
          ((@optic _.b.a.b[2]    ),   4  ),
          ((@optic _.b.a.b[i+1]  ),   4  ),
          ((@optic _.b.a.b[static(2)]   ),   4  ),
          ((@optic _.b.a.b[static((i+1))]),  4  ),
          ((@optic _.b.a.b[static(2)]   ),   4.0),
          ((@optic _.b.a.b[static((i+1))]),  4.0),
          ((@optic _             ),   obj),
          ((@optic _             ),   :xy),
        ]
        @inferred lens(obj)
        @inferred set(obj, lens, val)
        @inferred modify(identity, obj, lens)
    end

    @testset "$lens" for (lens, val) ∈ [
          ((@optic _.b.a.b[end]),     4.0),
          ((@optic _.b.a.b[end÷2+1]), 4.0),
         ]
        if VERSION < v"1.7"
            @test begin
                @inferred lens(obj)
                @inferred set(obj, lens, val)
                @inferred modify(identity, obj, lens)
                true
            end
        else
            @inferred lens(obj)
            @inferred set(obj, lens, val)
            @test_broken begin
                # https://github.com/JuliaLang/julia/issues/43296
                @inferred modify(identity, obj, lens)
                true
            end
        end
    end
end

@testset "IndexLens" begin
    l = @optic _[]
    @test l isa Accessors.IndexLens
    x = randn()
    obj = Ref(x)
    @test l(obj) == x

    l = @optic _[][]
    @test l.outer isa Accessors.IndexLens
    @test l.inner isa Accessors.IndexLens
    inner = Ref(x)
    obj = Base.RefValue{typeof(inner)}(inner)
    @test l(obj) == x

    obj = (1,2,3)
    l = @optic _[1]
    @test l isa Accessors.IndexLens
    @test l(obj) == 1
    @test set(obj, l, 6) == (6,2,3)


    l = @optic _[1:3]
    @test l isa Accessors.IndexLens
    @test l([4,5,6,7]) == [4,5,6]

    nt = (a=1, b=2, c=3)
    l = @optic _[(:a, :c)]
    @test l isa Accessors.IndexLens
    VERSION >= v"1.7" && @test l(nt) === (a=1, c=3)
    @test set(nt, l, ('1', '2')) === (a='1', b=2, c='2')
    @test set(nt, l, (c='2', a='1')) === (a='1', b=2, c='2')
end

@testset "DynamicIndexLens" begin
    l = @optic _[end]
    @test l isa Accessors.DynamicIndexLens
    obj = (1,2,3)
    @test l(obj) == 3
    @test set(obj, l, true) == (1,2,true)

    l = @optic _[end÷2]
    @test l isa Accessors.DynamicIndexLens
    obj = (1,2,3)
    @test l(obj) == 1
    @test set(obj, l, true) == (true,2,3)

    two = 2
    plusone(x) = x + 1
    l = @optic _.a[plusone(end) - two].b
    obj = (a=(1, (a=10, b=20), 3), b=4)
    @test l(obj) == 20
    @test set(obj, l, true) == (a=(1, (a=10, b=true), 3), b=4)
    if VERSION ≥ v"1.5.0-DEV.666"
        # parser is confused by x[begin] on older julia versions
        l = eval(Meta.parse("@optic _[begin]"))
        @test l isa Accessors.DynamicIndexLens
        obj = (1,2,3)
        @test l(obj) == 1
        @test set(obj, l, true) == (true,2,3)

        l = eval(Meta.parse("@optic _[2*begin]"))
        @test l isa Accessors.DynamicIndexLens
        obj = (1,2,3)
        @test l(obj) == 2
        @test set(obj, l, true) == (1,true,3)

        l = eval(Meta.parse(
        """
        let
            one = 1
            plustwo(x) = x + 2
            @optic _.a[plustwo(begin) - one].b
        end
        """))
        obj = (a=(1, (a=10, b=20), 3), b=4)
        @test l(obj) == 20
        @test set(obj, l, true) == (a=(1, (a=10, b=true), 3), b=4)
    end
end

@testset "StaticNumbers" begin
    obj = (1, 2.0, '3')
    l = @optic _[static(1)]
    @test (@inferred l(obj)) === 1
    @test (@inferred set(obj, l, 6.0)) === (6.0, 2.0, '3')
    l = @optic _[static(1 + 1)]
    @test (@inferred l(obj)) === 2.0
    @test (@inferred set(obj, l, 6)) === (1, 6, '3')
    n = 1
    l = @optic _[static(3n)]
    @test (@inferred l(obj)) === '3'
    @test (@inferred set(obj, l, 6)) === (1, 2.0, 6)

    l = @optic _[static(1):static(3)]
    @test l([4,5,6,7]) == [4,5,6]

    @testset "complex example (sweeper)" begin
        sweeper_with_const = (
            model = (1, 2.0, 3im),
            axis = (@optic _[static(2)]),
        )

        sweeper_with_noconst = @set sweeper_with_const.axis = @optic _[2]

        function f(s)
            a = sum(set(s.model, s.axis, 0))
            for i in 1:10
                a += sum(set(s.model, s.axis, i))
            end
            return a
        end

        @test (@inferred f(sweeper_with_const)) == 66 + 33im
        @test_broken (@inferred f(sweeper_with_noconst)) == 66 + 33im
    end
end

mutable struct M
    a
    b
end

@testset "IdentityLens" begin
    @test identity === @optic(_)
end

struct ABC{A,B,C}
    a::A
    b::B
    c::C
end

@testset "type change during @set (default constructorof)" begin
    obj = TT(2,3)
    obj2 = @set obj.b = :three
    @test obj2 === TT(2, :three)
end

# https://github.com/tkf/Reconstructables.jl#how-to-use-type-parameters
struct B{T, X, Y}
    x::X
    y::Y
    B{T}(x::X, y::Y = 2) where {T, X, Y} = new{T, X, Y}(x, y)
end
ConstructionBase.constructorof(::Type{<: B{T}}) where T = B{T}

@testset "type change during @set (custom constructorof)" begin
    obj = B{1}(2,3)
    obj2 = @set obj.y = :three
    @test obj2 === B{1}(2, :three)
end

@testset "Named Tuples" begin
    t = (x=1, y=2)
    @test (@set t.x =2) === (x=2, y=2)
    @test (@set t.x += 2) === (x=3, y=2)
    @test (@set t.x =:hello) === (x=:hello, y=2)
    l = @optic _.x
    @test l(t) === 1

    # do we want this to throw an error?
    @test_throws ArgumentError (@set t.z = 3)
end

struct CustomProperties
    _a
    _b
end

function ConstructionBase.setproperties(o::CustomProperties, patch::NamedTuple)
    CustomProperties(get(patch, :a, getfield(o, :_a)),
                     get(patch, :b, getfield(o, :_b)))

end

ConstructionBase.constructorof(::Type{CustomProperties}) = error()

@testset "setproperties overloading" begin
    o = CustomProperties("A", "B")
    o2 = @set o.a = :A
    @test o2 == CustomProperties(:A, "B")
    o3 = @set o.b = :B
    @test o3 == CustomProperties("A", :B)
end

@testset "issue #83" begin
    @test_throws ArgumentError Accessors.opticmacro(identity, :(_.[:a]))
end

@testset "|>" begin
    lbc = @optic _.b.c
    @test @optic(_ |> lbc) === lbc
    @test @optic(_.a |> lbc) === opcompose(@optic(_.a), lbc)
    @test @optic((_.a |> lbc).d) === opcompose(@optic(_.a), lbc , @optic(_.d))
    @test @optic(_.a |> lbc |> (@optic _[1]) |> lbc) ===
        opcompose(@optic(_.a), lbc, @optic(_[1]), lbc)

    @test @optic(_ |> _) === identity
    @test (@optic _ |> _[1])            === (@optic _[1])
    @test (@optic _ |> _.a)             === (@optic _.a)
    @test (@optic _ |> _.a.b)           === (@optic _.a.b)
    @test (@optic _ |> _.a[2])          === (@optic _.a[2])
    @test (@optic _ |> first |> _[1])   === (@optic first(_)[1])
    @test (@optic _ |> identity(first)) === first
    twice = lens -> lens ∘ lens
    @test (@optic _ |> twice(first)) === first ∘ first
    @test (@optic _ |> first |> _.a |> (first ∘ last) |> _[2]) ===
        (@optic (first ∘ last)(first(_).a)[2])
    @test (@optic _ |> _[1] |> _[2] |> _[3]) === @optic _[1][2][3]
end

if !Accessors.BASE_COMPOSED_FUNCTION_HAS_SHOW
    @info "Skipping show tests, on old VERSION = $VERSION"
else
    @testset "text/plain show" begin
        @testset for lens in [
            LensIfTextPlain()
        ]
            @test occursin("I define text/plain.", sprint(show, "text/plain", lens))
        end
        @testset for lens in [
            @optic _.a |> LensIfTextPlain()
            @optic _ |> LensIfTextPlain() |> _.b
            @optic _.a |> LensIfTextPlain() |> @optic _.b
        ]
            @test_broken occursin("I define text/plain.", sprint(show, "text/plain", lens))
        end

        @testset for lens in [
            UserDefinedLens()
            @optic _.a |> UserDefinedLens()
            @optic _ |> UserDefinedLens() |> _.b
            @optic _.a |> UserDefinedLens() |> _.b
        ]
            @test sprint(show, lens) == sprint(show, "text/plain", lens)
        end
    end

    @testset "show it like you build it " begin
        @testset for item in [
                @optic _.a
                @optic _[1]
                @optic _[:a]
                @optic _["a"]
                @optic _[static(1)]
                @optic _[static(1), static(1 + 1)]
                @optic _.a.b[:c]["d"][2][static(3)]
                @optic _
                @optic first(_)
                @optic last(first(_))
                @optic last(first(_.a))[1]
                UserDefinedLens()
                @optic _ |> UserDefinedLens()
                @optic UserDefinedLens()(_)
                @optic _ |> ((x -> x)(first))
                @optic _.a |> UserDefinedLens()
                @optic _ |> UserDefinedLens() |> _.b
                (@optic _.a) ∘ UserDefinedLens()   ∘ (@optic _.b)
                (@optic _.a) ∘ LensIfTextPlain() ∘ (@optic _.b)
            ]
            buf = IOBuffer()
            show(buf, item)
            item2 = eval(Meta.parse(String(take!(buf))))
            @test item === item2
        end
    end
end

@testset "@modify" begin
    obj = (field=4,)
    ret = @modify(obj.field) do x
        x + 1
    end
    expected = (field=5,)
    @test ret === expected
    @test obj === (field = 4,)

    @test expected === @modify(x -> x+1, obj.field)
    f = x -> x+1
    @test expected === @modify(f, obj.field)
    @test expected === @modify f obj.field
end

@testset "equality & hashing" begin
    # singletons (identity and property optic) are egal
    for (l1, l2) ∈ [
        @optic(_) => @optic(_),
        @optic(_.a) => @optic(_.a)
    ]
        @test l1 === l2
        @test l1 == l2
        @test hash(l1) == hash(l2)
    end

    # composite and index optices are structurally equal
    for (l1, l2) ∈ [
        @optic(_[1]) => @optic(_[1])
        @optic(_.a[2]) => @optic(_.a[2])
        @optic(_.a.b[3]) => @optic(_.a.b[3])
    ]
        @test l1 == l2
        @test hash(l1) == hash(l2)
    end

    # inequality
    for (l1, l2) ∈ [
        @optic(_[1]) => @optic(_[2])
        @optic(_.a[1]) => @optic(_.a[2])
        @optic(_.a[1]) => @optic(_.b[1])
    ]
        @test l1 != l2
    end

    # Hash property: equality implies equal hashes, or in other terms:
    # optices either have equal hashes or are unequal
    # Because collisions can occur theoretically (though unlikely), this is a property test,
    # not a unit test.
    random_optices = (@optic(_.a[rand(Int)]) for _ in 1:1000)
    @test all((hash(l2) == hash(l1)) || (l1 != l2)
              for (l1, l2) in zip(random_optices, random_optices))

    # Lenses should hash differently from the underlying tuples, to avoid confusion.
    # To account for potential collisions, we check that the property holds with high
    # probability.
    @test count(hash(@optic(_[i])) != hash((i,)) for i = 1:1000) > 900

    # Same for tuples of tuples (√(1000) ≈ 32).
    @test count(hash(@optic(_[i][j])) != hash(((i,), (j,))) for i = 1:32, j = 1:32) > 900
end

end
