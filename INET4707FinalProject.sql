drop database if exists bar_inventory;
create database bar_inventory;
use bar_inventory;

create table suppliers(
supplier_id int not null auto_increment primary key,
name varchar(50),
contact_info varchar(100),
address varchar(100)
);

create table product_inventory(
product_id int auto_increment primary key,
name enum('whiskey', 'vodka', 'rum', 'gin', 'tequila'),
brand varchar(50),
type enum('beer', 'wine', 'spirits'),
quantity decimal (10, 2),
unit_price decimal (10, 2)
);

create table supplier_details(
supplier_id int,
product_id int,
foreign key (product_id) references product_inventory(product_id),
foreign key (supplier_id) references suppliers(supplier_id)
);

create table drinks(
drink_id int auto_increment not null primary key,
name varchar(50),
price decimal (10, 2)
);

create table drink_ingredients(
drink_ingredient int auto_increment not null primary key,
drink_id int, 
ingredient_type enum('hard_liquor', 'non_alcoholic', 'cordials_liqueurs'),
ingredient_id int,
quantity int,
foreign key (drink_id) references drinks(drink_id),
foreign key (ingredient_id) references product_inventory(product_id)
);

create table orders(
order_id int auto_increment not null primary key,
supplier_id int,
order_date date,
total_amount decimal (10, 2),
foreign key(supplier_id) references suppliers(supplier_id)
);

create table order_details(
order_detail_id int auto_increment not null primary key,
order_id int,
product_id int, 
quantity int, 
unit_price decimal (10, 2),
foreign key (order_id) references orders(order_id),
foreign key (product_id) references product_inventory(product_id)
);

create table sales(
sale_id int auto_increment not null primary key,
sale_date date,
sale_total decimal (10, 2),
tip decimal (10, 2) default 0,
total_amount decimal (10, 2)
);

create table sales_archive(
sale_id int auto_increment not null primary key,
sale_date date,
sale_total decimal (10, 2),
tip decimal (10, 2),
total_amount decimal (10, 2),
foreign key (sale_id) references sales(sale_id)
);

create table employees(
employee_id int auto_increment not null primary key,
name varchar(50),
position varchar(50),
contact_info varchar(100)
);

create table sale_details(
sale_detail_id int auto_increment not null primary key,
sale_id int,
drink_id int,
quantity int,
unit_price decimal (10, 2),
employee_id int,
foreign key(sale_id) references sales(sale_id),
foreign key(drink_id) references drinks(drink_id),
foreign key(employee_id) references employees(employee_id)
);

create table inventory_adjustments(
adjustment_id int auto_increment not null primary key,
product_id int,
adjustment_date date,
quantity_change int,
reason enum('spilled', 'theft', 'promotion'),
foreign key (product_id) references product_inventory(product_id)
);

create table customers(
customer_id int auto_increment not null primary key,
name varchar(50), 
contact_info varchar(50)
);

create table customer_orders(
customer_order_id int auto_increment not null primary key,
customer_id int,
sale_id int,
order_date date,
total_amount decimal (10, 2),
foreign key (customer_id) references customers(customer_id),
foreign key (sale_id) references sales(sale_id)
);

-- list of stock of all products by name
create view total_product_stock as
select p.name as product_name,
sum(p.quantity) as total_product_stock
from product_inventory p
group by p.name;

-- list of product sales by day
create view daily_sales as
select date(sale_date) as sale_date,
sum(total_amount) as total_sales
from sales 
group by date(sale_date)
order by sale_date;

-- list of top sales grouped by month
create view top_monthly_sales as
select date_format(sale_date, '%Y-%m') as month,
sum(total_amount) as total_sales
from sales 
group by date_format(sale_date, '%Y-%m')
order by total_sales desc;

-- list of sales organized by employee
create view sales_by_employee as
select e.name as employee_name,
sum(sd.quantity * sd.unit_price) as total_sales 
from sales s 
join sale_details sd on s.sale_id = sd.sale_id
join employees e on sd.employee_id = e.employee_id
group by e.name
order by total_sales desc;

delimiter // 
-- applies inventory adjustment to product inventory
create trigger after_inventory_adjustment
after insert on inventory_adjustments
for each row
begin
	update product_inventory
    set quantity = quantity + new.quantity_change
    where product_id = new.product_id;
end //

-- ensures sale record is made with all drink ingredients accounted for
create trigger after_sale_record
after insert on sale_details
for each row 
begin
	declare done int default false;
    declare product_id int;
    declare product_quantity decimal (10, 2);
    
    declare cur cursor for
		select dp.ingredient_id, dp.quantity
        from drink_ingredients dp
        where dp.drink_id = new.drink_id;
        
	declare continue handler for not found set done = true;
    
    open cur;
    
    read_loop: loop
		fetch cur into product_id, product_quantity;
        if done then 
			leave read_loop;
		end if;
        -- each ingredient of a drink will be about of ~1/22nd of a bottle
        -- bars usually buy liters
        update product_inventory
        set quantity = quantity - (product_quantity * new.quantity / 22)
        where product_id = product_id;
	end loop;
	
    close cur;
end // 

-- updates total amount in orders when the order details are updated
create trigger after_order_detail_insert
after insert on order_details
for each row
begin
	update orders
    set total_amount = total_amount + (new.quantity + new.unit_price)
    where order_id = new.order_id;
end // 

-- archives old sales before they're deleted
create trigger before_sale_delete
before delete on sales
for each row
begin 
	insert into sales_archive (sale_id, sale_date, sale_total, tip, total_amount)
	values (old.sale_id, old.sale_date, old.sale_total, old.tip, old.total_amount);
end //

-- updates total amount of sales once tip is updated
create trigger after_tip_update
after update on sales 
for each row
begin
	update sales
    set total_amount = sale_total + new.tip
    where sale_id = new.sale.id;
end //

-- makes an order to restock inventory once 36 units is reached
create procedure restock_inventory()
begin
	declare done int default false;
    declare product_id int;
    declare product_name varchar(50);
    declare current_quantity int;
    declare reorder_level decimal (10, 2) default 36;
    declare reorder_quantity int default 72;
    
    declare cur cursor for 
		select product_id, name, quantity
        from product_inventory
        where quantity < reorder_level;
        
	declare continue handler for not found set done = true;
    
    open cur;
    
    read_loop: loop
		fetch cur into product_id, product_name, current_quantity;
        if done 
			then leave read_loop;
        end if;
        
        insert into orders (supplier_id, order_date, total_amount)
        values ((select supplier_id from product_inventory where product_id = product_id), now(), 
        reorder_quantity * (select unit_price from product_inventory where product_id = product_id));
        
        set @last_order_id = last_insert_id();
        
        insert into order_Details (order_id, product_id, quantity, unit_price)
        values (@last_order_id, product_id, reorder_quantity, 
        (select unit_price from product_inventory where product_id = product_id));
        
        update product_inventory
        set quantity = quantity + reorder_quantity
        where id = product_id;
	
    end loop;
    
    close cur;
end //

delimiter ;

-- Example Records
INSERT INTO suppliers (name, contact_info, address) VALUES
('Supplier A', 'contactA@example.com', '123 Main St'),
('Supplier B', 'contactB@example.com', '456 Oak St'),
('Supplier C', 'contactC@example.com', '789 Pine St'),
('Supplier D', 'contactD@example.com', '101 Maple St'),
('Supplier E', 'contactE@example.com', '202 Birch St'),
('Supplier F', 'contactF@example.com', '303 Cedar St'),
('Supplier G', 'contactG@example.com', '404 Elm St'),
('Supplier H', 'contactH@example.com', '505 Spruce St'),
('Supplier I', 'contactI@example.com', '606 Willow St'),
('Supplier J', 'contactJ@example.com', '707 Ash St');

INSERT INTO product_inventory (name, brand, type, quantity, unit_price) VALUES
('whiskey', 'Brand A', 'spirits', 50.00, 20.00),
('vodka', 'Brand B', 'spirits', 60.00, 15.00),
('rum', 'Brand C', 'spirits', 70.00, 18.00),
('gin', 'Brand D', 'spirits', 80.00, 22.00),
('tequila', 'Brand E', 'spirits', 90.00, 25.00),
('whiskey', 'Brand F', 'spirits', 55.00, 21.00),
('vodka', 'Brand G', 'spirits', 65.00, 16.00),
('rum', 'Brand H', 'spirits', 75.00, 19.00),
('gin', 'Brand I', 'spirits', 85.00, 23.00),
('tequila', 'Brand J', 'spirits', 95.00, 26.00);

INSERT INTO supplier_details (supplier_id, product_id) VALUES
(1, 1),
(2, 2),
(3, 3),
(4, 4),
(5, 5),
(6, 6),
(7, 7),
(8, 8),
(9, 9),
(10, 10);

INSERT INTO drinks (name, price) VALUES
('Margarita', 8.00),
('Mojito', 7.50),
('Old Fashioned', 9.00),
('Martini', 10.00),
('Cosmopolitan', 8.50),
('Daiquiri', 7.00),
('Manhattan', 9.50),
('Whiskey Sour', 8.00),
('Pina Colada', 7.50),
('Bloody Mary', 8.00);

INSERT INTO drink_ingredients (drink_id, ingredient_type, ingredient_id, quantity) VALUES
(1, 'hard_liquor', 1, 1),
(1, 'non_alcoholic', 2, 1),
(2, 'hard_liquor', 2, 1),
(2, 'non_alcoholic', 3, 1),
(3, 'hard_liquor', 3, 1),
(3, 'non_alcoholic', 4, 1),
(4, 'hard_liquor', 4, 1),
(4, 'non_alcoholic', 5, 1),
(5, 'hard_liquor', 5, 1),
(5, 'non_alcoholic', 6, 1);

INSERT INTO orders (supplier_id, order_date, total_amount) VALUES
(1, '2024-01-01', 1000.00),
(2, '2024-01-02', 1200.00),
(3, '2024-01-03', 1100.00),
(4, '2024-01-04', 1300.00),
(5, '2024-01-05', 1400.00),
(6, '2024-01-06', 1500.00),
(7, '2024-01-07', 1600.00),
(8, '2024-01-08', 600.00),
(9, '2024-01-09', 360.00),
(10, '2024-01-10', 450.00);

INSERT INTO order_details (order_id, product_id, quantity, unit_price) VALUES
(1, 1, 50, 20.00),
(2, 2, 60, 15.00),
(3, 3, 70, 18.00),
(4, 4, 80, 22.00),
(5, 5, 90, 25.00),
(6, 6, 55, 21.00),
(7, 7, 65, 16.00),
(8, 8, 75, 8.00),
(9, 9, 85, 4.00),
(10, 10, 95, 5.00);

INSERT INTO sales (sale_date, sale_total, tip, total_amount) VALUES
('2024-01-01', 50.00, 20.00, 70.00),
('2024-01-02', 60.00, 15.00, 75.00),
('2024-01-03', 70.00, 14.00, 84.00),
('2024-01-04', 80.00, 8.00, 88.00),
('2024-01-05', 90.00, 0.00, 90.00),
('2024-01-06', 100.00, 10.00, 110.00),
('2024-01-07', 110.00, 110.00, 220.00),
('2024-01-08', 10.00, 12.00, 22.00),
('2024-01-09', 105.00, 13.00, 118.00),
('2024-01-10', 60.00, 14.00, 74.00);

INSERT INTO sales_archive (sale_id, sale_date, sale_total, tip, total_amount) VALUES
(1, '2024-01-01', 50.00, 20.00, 70.00),
(2, '2024-01-02', 60.00, 15.00, 75.00),
(3, '2024-01-03', 70.00, 14.00, 84.00),
(4, '2024-01-04', 80.00, 8.00, 88.00),
(5, '2024-01-05', 90.00, 0.00, 90.00),
(6, '2024-01-06', 100.00, 10.00, 110.00),
(7, '2024-01-07', 110.00, 110.00, 220.00),
(8, '2024-01-08', 10.00, 12.00, 22.00),
(9, '2024-01-09', 105.00, 13.00, 118.00),
(10, '2024-01-10', 60.00, 14.00, 74.00);

INSERT INTO employees (name, position, contact_info) VALUES
('John Doe', 'Bartender', 'john@example.com'),
('Jane Smith', 'Manager', 'jane@example.com'),
('Bob Johnson', 'Waiter', 'bob@example.com'),
('Alice Brown', 'Waitress', 'alice@example.com'),
('Charlie Davis', 'Chef', 'charlie@example.com'),
('Eve Wilson', 'Hostess', 'eve@example.com'),
('Frank Miller', 'Security', 'frank@example.com'),
('Grace Lee', 'Cleaner', 'grace@example.com'),
('Hank Green', 'Dishwasher', 'hank@example.com'),
('Ivy White', 'Cashier', 'ivy@example.com');

INSERT INTO sale_details (sale_id, drink_id, quantity, unit_price, employee_id) VALUES
(1, 1, 2, 8.00, 1),
(2, 2, 3, 7.50, 2),
(3, 3, 1, 9.00, 3),
(4, 4, 2, 10.00, 4),
(5, 5, 3, 8.50, 5),
(6, 6, 1, 8.00, 6),
(7, 7, 2, 7.50, 7),
(8, 8, 1, 9.00, 8),
(9, 9, 2, 8.00, 9),
(10, 10, 3, 7.50, 10);


INSERT INTO inventory_adjustments (product_id, adjustment_date, quantity_change, reason) VALUES
(1, '2024-01-01', -2, 'spilled'),
(2, '2024-01-02', -1, 'theft'),
(3, '2024-01-03', -3, 'promotion'),
(4, '2024-01-04', -2, 'spilled'),
(5, '2024-01-05', -1, 'theft'),
(6, '2024-01-06', -5, 'promotion'),
(7, '2024-01-07', -4, 'spilled'),
(8, '2024-01-08', -2, 'theft'),
(9, '2024-01-09', 20, 'promotion'),
(10, '2024-01-10', -3, 'spilled');

INSERT INTO customers (name, contact_info) VALUES
('Alice Johnson', 'alice@example.com'),
('Bob Smith', 'bob@example.com'),
('Charlie Brown', 'charlie@example.com'),
('David Wilson', 'david@example.com'),
('Eve Davis', 'eve@example.com'),
('Frank Miller', 'frank@example.com'),
('Grace Lee', 'grace@example.com'),
('Hank Green', 'hank@example.com'),
('Ivy White', 'ivy@example.com'),
('Jack Black', 'jack@example.com');


INSERT INTO customer_orders (customer_id, sale_id, order_date, total_amount) VALUES
(1, 1, '2024-01-01', 70.00),
(2, 2, '2024-01-02', 75.00),
(3, 3, '2024-01-03', 84.00),
(4, 4, '2024-01-04', 88.00),
(5, 5, '2024-01-05', 90.00),
(6, 6, '2024-01-06', 110.00),
(7, 7, '2024-01-07', 220.00),
(8, 8, '2024-01-08', 22.00),
(9, 9, '2024-01-09', 118.00),
(10, 10, '2024-01-10', 74.00);



select e.name as employee_name,
sum(sd.quantity * sd.unit_price) as total_sales 
from sales s 
join sale_details sd on s.sale_id = sd.sale_id
join employees e on sd.employee_id = e.employee_id
group by e.name
order by total_sales desc;




