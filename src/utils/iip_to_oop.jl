function IIP_to_OOP(f_iip)
    function f_oop(u, p, t)
        println("Hello")
        println(size(u))
        du = _copy(u)
        f_iip(du, u, p, t)
        return du
    end
    return f_oop
end
